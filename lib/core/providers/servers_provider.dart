import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../models/server_model.dart';
import '../models/subscription_model.dart';
import '../models/vpn_status.dart';
import '../services/storage_service.dart';
import '../services/subscription_service.dart';
import '../utils/geo_utils.dart';
import '../utils/link_parser.dart';
import '../utils/ping_utils.dart';

class ServersProvider extends ChangeNotifier {
  ServersProvider(this._storage, this._subscriptions);

  final StorageService _storage;
  final SubscriptionService _subscriptions;
  final _uuid = const Uuid();
  Timer? _timer;

  List<ServerModel> servers = [];
  List<SubscriptionModel> subscriptions = [];
  bool pinging = false;
  bool refreshing = false;
  final Set<String> pingingSubscriptions = <String>{};
  String query = '';
  String? protocolFilter;
  String? countryFilter;
  bool onlyAvailable = false;
  bool onlyAntiblock = false;
  String sort = 'manual';

  Future<void> load() async {
    final serverJson = _storage.readJson('servers');
    final subJson = _storage.readJson('subscriptions');
    servers = (serverJson?['items'] as List?)
            ?.whereType<Map>()
            .map((e) => ServerModel.fromJson(
                  e.map((k, v) => MapEntry(k.toString(), v)),
                ))
            .toList() ??
        [];
    subscriptions = (subJson?['items'] as List?)
            ?.whereType<Map>()
            .map((e) => SubscriptionModel.fromJson(
                  e.map((k, v) => MapEntry(k.toString(), v)),
                ))
            .toList() ??
        [];
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => refreshDue());
    notifyListeners();
  }

  Future<void> _persist() async {
    await _storage.writeJson('servers', {
      'items': servers.map((e) => e.toJson()).toList(),
    });
    await _storage.writeJson('subscriptions', {
      'items': subscriptions.map((e) => e.toJson()).toList(),
    });
  }

  List<ServerModel> serversOf(String? subscriptionId) {
    return servers.where((s) => s.subscriptionId == subscriptionId).toList();
  }

  ServerModel? byId(String? id) {
    if (id == null) return null;
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  List<ServerModel> get filtered {
    final q = query.trim().toLowerCase();
    final list = servers.where((server) {
      if (protocolFilter != null && server.protocol != protocolFilter) {
        return false;
      }
      if (countryFilter != null && server.countryCode != countryFilter) {
        return false;
      }
      if (onlyAvailable && !server.isAvailable) return false;
      if (onlyAntiblock && !server.isBridge) return false;
      if (q.isEmpty) return true;
      final country = GeoUtils.countryName(server.countryCode, ru: true)
          .toLowerCase();
      return server.name.toLowerCase().contains(q) ||
          server.address.toLowerCase().contains(q) ||
          server.protocol.contains(q) ||
          country.contains(q) ||
          (server.countryCode ?? '').toLowerCase().contains(q);
    }).toList();
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      switch (sort) {
        case 'ping':
          final ap = a.pingMs ?? 100000;
          final bp = b.pingMs ?? 100000;
          final an = ap < 0 ? 100000 : ap;
          final bn = bp < 0 ? 100000 : bp;
          return an.compareTo(bn);
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default:
          return 0;
      }
    });
    return list;
  }

  List<SubscriptionModel> get orderedSubscriptions {
    final list = List<SubscriptionModel>.from(subscriptions);
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.order != b.order) return a.order.compareTo(b.order);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Lowest ping among the servers of a subscription, or `null` when nothing
  /// was measured yet.
  int? subscriptionPing(String subscriptionId) {
    final values = serversOf(subscriptionId)
        .map((server) => server.pingMs)
        .whereType<int>()
        .where((ms) => ms >= 0)
        .toList()
      ..sort();
    return values.isEmpty ? null : values.first;
  }

  bool subscriptionPinging(String subscriptionId) =>
      pingingSubscriptions.contains(subscriptionId);

  /// Pings only the servers that belong to one subscription.
  Future<void> pingSubscription(String subscriptionId) async {
    final targets = serversOf(subscriptionId)
        .map((server) => (id: server.id, host: server.address, port: server.port))
        .toList();
    if (targets.isEmpty || pingingSubscriptions.contains(subscriptionId)) return;
    pingingSubscriptions.add(subscriptionId);
    notifyListeners();
    try {
      await PingUtils.pingAll(
        targets,
        onEach: (id, ms) {
          final server = byId(id);
          if (server == null) return;
          server
            ..pingMs = ms
            ..lastPingAt = DateTime.now();
          notifyListeners();
        },
      );
    } finally {
      pingingSubscriptions.remove(subscriptionId);
      await _persist();
      notifyListeners();
    }
  }

  /// Moves a subscription one slot up (`delta` < 0) or down (`delta` > 0) in
  /// the list the user sees.
  Future<void> moveSubscription(String id, int delta) async {
    if (delta == 0) return;
    final ordered = orderedSubscriptions;
    final index = ordered.indexWhere((sub) => sub.id == id);
    if (index < 0) return;
    final target = index + delta;
    if (target < 0 || target >= ordered.length) return;
    final current = ordered[index];
    final other = ordered[target];
    final currentOrder = current.order;
    current.order = other.order;
    other.order = currentOrder;
    await _persist();
    notifyListeners();
  }

  Future<int> addDrafts(
    List<ServerDraft> drafts, {
    String? subscriptionId,
    bool markNew = false,
  }) async {
    var added = 0;
    for (final draft in drafts) {
      final existing = servers.where((server) {
        return server.subscriptionId == subscriptionId &&
            server.fingerprint ==
                '${draft.protocol}|${draft.address.toLowerCase()}|${draft.port}|${draft.name.toLowerCase()}';
      }).firstOrNull;
      if (existing != null) {
        existing
          ..rawLink = draft.rawLink ?? existing.rawLink
          ..outbound = draft.outbound ?? existing.outbound
          ..endpoint = draft.endpoint ?? existing.endpoint
          ..tags = draft.tags
          ..countryCode = draft.countryCode ?? existing.countryCode;
        continue;
      }
      servers.add(ServerModel(
        id: _uuid.v4(),
        name: draft.name,
        address: draft.address,
        port: draft.port,
        protocol: draft.protocol,
        countryCode: draft.countryCode,
        tags: List<String>.from(draft.tags),
        subscriptionId: subscriptionId,
        rawLink: draft.rawLink,
        outbound: draft.outbound,
        endpoint: draft.endpoint,
        isNew: markNew,
        createdAt: DateTime.now(),
      ));
      added++;
    }
    await _persist();
    notifyListeners();
    return added;
  }

  Future<SubscriptionModel> addSubscription(String url, {String? name}) async {
    final nextOrder = subscriptions.isEmpty
        ? 0
        : subscriptions.map((e) => e.order).reduce((a, b) => a > b ? a : b) + 1;
    final sub = SubscriptionModel(
      id: _uuid.v4(),
      name: name ?? _nameFromUrl(url),
      url: url.trim(),
      autoUpdateInterval: UpdateInterval.hour6,
      order: nextOrder,
    );
    subscriptions.add(sub);
    await _persist();
    notifyListeners();
    await refreshSubscription(sub.id);
    return sub;
  }

  Future<void> refreshSubscription(String id) async {
    final sub = subscriptions.where((s) => s.id == id).firstOrNull;
    if (sub == null) return;
    refreshing = true;
    notifyListeners();
    try {
      final fetched = await _subscriptions.fetch(sub);
      final previous = serversOf(id).map((e) => e.fingerprint).toSet();
      servers.removeWhere(
        (server) =>
            server.subscriptionId == id &&
            !server.isPinned &&
            !fetched.servers.any((draft) =>
                '${draft.protocol}|${draft.address.toLowerCase()}|${draft.port}|${draft.name.toLowerCase()}' ==
                server.fingerprint),
      );
      await addDrafts(
        fetched.servers,
        subscriptionId: id,
        markNew: previous.isNotEmpty,
      );
      for (final server in serversOf(id)) {
        if (previous.contains(server.fingerprint)) server.isNew = false;
      }
      sub
        ..lastUpdated = DateTime.now()
        ..lastError = null
        ..uploadBytes = fetched.uploadBytes ?? sub.uploadBytes
        ..downloadBytes = fetched.downloadBytes ?? sub.downloadBytes
        ..totalBytes = fetched.totalBytes ?? sub.totalBytes
        ..expireAt = fetched.expireAt ?? sub.expireAt;
      if (fetched.title != null &&
          fetched.title!.isNotEmpty &&
          sub.name == _nameFromUrl(sub.url)) {
        sub.name = fetched.title!;
      }
      if (fetched.intervalMinutes != null &&
          sub.autoUpdateInterval == UpdateInterval.manual) {
        sub.autoUpdateInterval =
            UpdateInterval.fromMinutes(fetched.intervalMinutes!);
      }
    } catch (error) {
      sub.lastError = '$error';
    }
    refreshing = false;
    await _persist();
    notifyListeners();
  }

  Future<void> refreshDue() async {
    for (final sub in List<SubscriptionModel>.from(subscriptions)) {
      if (sub.isDue) await refreshSubscription(sub.id);
    }
  }

  Future<void> refreshAll() async {
    for (final sub in List<SubscriptionModel>.from(subscriptions)) {
      await refreshSubscription(sub.id);
    }
  }

  Future<void> updateSubscription(
    String id, {
    String? name,
    String? url,
    UpdateInterval? interval,
    String? userAgent,
    bool? pinned,
  }) async {
    final sub = subscriptions.where((s) => s.id == id).firstOrNull;
    if (sub == null) return;
    if (name != null) sub.name = name;
    if (url != null) sub.url = url;
    if (interval != null) sub.autoUpdateInterval = interval;
    if (userAgent != null) sub.userAgent = userAgent;
    if (pinned != null) sub.isPinned = pinned;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteSubscription(String id) async {
    subscriptions.removeWhere((s) => s.id == id);
    servers.removeWhere((s) => s.subscriptionId == id);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteServer(String id) async {
    servers.removeWhere((s) => s.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> updateServer(ServerModel server) async {
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index < 0) return;
    servers[index] = server;
    await _persist();
    notifyListeners();
  }

  Future<void> togglePin(String id) async {
    final server = byId(id);
    if (server == null) return;
    server.isPinned = !server.isPinned;
    await _persist();
    notifyListeners();
  }

  Future<void> setPing(String id, int ms) async {
    final server = byId(id);
    if (server == null) return;
    server
      ..pingMs = ms
      ..lastPingAt = DateTime.now()
      ..isNew = false;
    notifyListeners();
  }

  Future<void> pingAll({void Function(String id, int ms)? onEach}) async {
    if (pinging || servers.isEmpty) return;
    pinging = true;
    notifyListeners();
    await PingUtils.pingAll(
      servers
          .map((s) => (id: s.id, host: s.address, port: s.port))
          .toList(),
      onEach: (id, ms) {
        final server = byId(id);
        if (server == null) return;
        server
          ..pingMs = ms
          ..lastPingAt = DateTime.now();
        onEach?.call(id, ms);
        notifyListeners();
      },
    );
    pinging = false;
    if (sort == 'manual') sort = 'ping';
    await _persist();
    notifyListeners();
  }

  Future<String> exportJson() async {
    return const JsonEncoder.withIndent('  ').convert({
      'subscriptions': subscriptions.map((e) => e.toJson()).toList(),
      'servers': servers.map((e) => e.toJson()).toList(),
    });
  }

  Future<void> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    final map = decoded.map((k, v) => MapEntry(k.toString(), v));
    if (map['outbounds'] is List || map['endpoints'] is List) {
      final parsed = LinkParser.parseInput(raw);
      await addDrafts(parsed.servers);
      return;
    }
    if (map['servers'] is List && map['subscriptions'] is List) {
      subscriptions = (map['subscriptions'] as List)
          .whereType<Map>()
          .map((e) => SubscriptionModel.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
      servers = (map['servers'] as List)
          .whereType<Map>()
          .map((e) => ServerModel.fromJson(
                e.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
      await _persist();
      notifyListeners();
    }
  }

  void setQuery(String value) {
    query = value;
    notifyListeners();
  }

  void setSort(String value) {
    sort = value;
    notifyListeners();
  }

  void setFilters({
    String? protocol,
    String? country,
    bool? availableOnly,
    bool? antiblockOnly,
    bool clearProtocol = false,
    bool clearCountry = false,
  }) {
    if (clearProtocol) protocolFilter = null;
    if (clearCountry) countryFilter = null;
    if (protocol != null) protocolFilter = protocol;
    if (country != null) countryFilter = country;
    if (availableOnly != null) onlyAvailable = availableOnly;
    if (antiblockOnly != null) onlyAntiblock = antiblockOnly;
    notifyListeners();
  }

  List<String> get protocols =>
      servers.map((e) => e.protocol).toSet().toList()..sort();

  List<String> get countries => servers
      .map((e) => e.countryCode)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();

  String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Subscription';
    return uri.host;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
