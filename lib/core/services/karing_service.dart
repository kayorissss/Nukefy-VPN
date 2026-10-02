import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';
import '../models/app_settings.dart';
import '../models/server_model.dart';
import '../models/subscription_model.dart';
import 'whitelist_mirrors.dart';

/// Karing-style whitelist-bypass engine.
///
/// Karing (KaringX/karing) is the reference client for the zieng2/wl
/// subscription: it keeps a latency balancer over the whole subscription,
/// filters Russian nodes out of the auto-select and routes everything through
/// the tunnel (no RU bypass rules). This service ports that behaviour onto the
/// sing-box core that Nukefy already ships, so the bypass works without a
/// second application.
class KaringService extends ChangeNotifier {
  KaringService._();
  static final KaringService instance = KaringService._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 10),
  ));

  bool checking = false;
  Map<String, bool> reachability = {};
  String? lastError;

  /// Cheap availability probe: a mirror counts as reachable when it answers
  /// with a non-empty body and a non-error status code.
  Future<bool> reachable(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'User-Agent': AppConstants.userAgent},
          validateStatus: (code) => code != null && code < 500,
        ),
      );
      final ok = response.statusCode != null &&
          response.statusCode! < 400 &&
          (response.data ?? '').trim().isNotEmpty;
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Probes every mirror in catalog order and remembers the result.
  Future<Map<String, bool>> checkMirrors() async {
    checking = true;
    lastError = null;
    notifyListeners();
    try {
      final results = <String, bool>{};
      for (final mirror in WhitelistCatalog.mirrors) {
        results[mirror.id] = await reachable(mirror.url);
      }
      reachability = results;
    } catch (error) {
      lastError = '$error';
    } finally {
      checking = false;
      notifyListeners();
    }
    return reachability;
  }

  /// First mirror that answers, stable hosts preferred.
  Future<WhitelistMirror?> firstReachable() async {
    for (final mirror in WhitelistCatalog.mirrors) {
      if (await reachable(mirror.url)) return mirror;
    }
    return null;
  }

  /// The server pool the sing-box urltest balancer should keep hot.
  ///
  /// The pool is the whitelist subscription the selected server belongs to;
  /// other subscriptions keep working as plain single outbounds. Empty when
  /// the bypass is off, when there is no whitelist subscription or when too
  /// few nodes survived the country filter — a balancer over one node is
  /// just a static outbound.
  static List<ServerModel> balancerPool({
    required List<ServerModel> servers,
    required List<SubscriptionModel> subscriptions,
    required AppSettings settings,
    required String? activeSubscriptionId,
  }) {
    if (!settings.karingEnabled || !settings.karingBalancer) return const [];
    if (activeSubscriptionId == null) return const [];
    final subscription = subscriptions
        .where((item) => item.id == activeSubscriptionId)
        .firstOrNull;
    if (subscription == null || !WhitelistCatalog.isWhitelistUrl(subscription.url)) {
      return const [];
    }
    final pool = servers
        .where((server) => server.subscriptionId == activeSubscriptionId)
        .where((server) => !server.isInformational)
        .where((server) =>
            !settings.karingExcludeRu || _excluded(server.countryCode) == false)
        .toList();
    return pool.length > 1 ? pool : const [];
  }

  static bool _excluded(String? countryCode) {
    final code = (countryCode ?? '').toLowerCase();
    return code == 'ru' || code == 'by';
  }

  /// sing-box urltest interval for the balancer.
  static const String balancerInterval = '4m';
  static const String balancerUrl = 'https://cp.cloudflare.com/generate_204';
}
