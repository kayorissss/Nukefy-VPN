import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/vpn_status.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/clash_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../widgets/section_card.dart';

/// "Анализ соединений": live connections from the running core (Clash API),
/// the real in-tunnel delay and the current external IP. When nothing is
/// connected it honestly says so instead of showing a pretty empty void.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final _api = ClashApi();
  Timer? _timer;
  List<Map<String, dynamic>> _connections = const [];
  int? _delay;
  bool _delayBusy = false;
  String? _ip;
  bool _ipBusy = false;
  String? _ipError;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final vpn = context.read<VpnProvider>();
    if (vpn.status != VpnStatus.connected || vpn.engine != 'singbox') return;
    try {
      final list = await _api.connections();
      if (mounted) setState(() => _connections = list);
    } catch (_) {
      // Core stopped between ticks: keep the last real snapshot.
    }
  }

  Future<void> _measureDelay() async {
    setState(() => _delayBusy = true);
    final delay = await _api.proxyDelay();
    if (!mounted) return;
    setState(() {
      _delay = delay;
      _delayBusy = false;
    });
  }

  /// External IP through the local HTTP proxy (or direct when the Xray
  /// engine serves the session — it uses the same HTTP port).
  Future<void> _checkIp() async {
    final s = context.read<SettingsProvider>().strings;
    final settings = context.read<SettingsProvider>().settings;
    setState(() {
      _ipBusy = true;
      _ipError = null;
    });
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
      ));
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY 127.0.0.1:${settings.httpPort}';
          client.connectionTimeout = const Duration(seconds: 8);
          return client;
        },
      );
      final response = await dio.get<String>('https://api.ipify.org');
      if (!mounted) return;
      setState(() {
        _ip = (response.data ?? '').trim();
        _ipBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ipBusy = false;
        _ipError = s.t('ipFail');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnProvider>();
    final settings = context.watch<SettingsProvider>();
    final s = settings.strings;
    final connected = vpn.status == VpnStatus.connected;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(s.t('analysis'), style: AppTextStyles.title),
          const SizedBox(height: 14),
          SectionCard(
            title: s.t('myIp'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _ipBusy
                            ? s.t('ipChecking')
                            : _ipError ?? _ip ?? '—',
                        style: AppTextStyles.monoValue.copyWith(fontSize: 16),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _ipBusy ? null : _checkIp,
                      child: Text(s.t('checkIp')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? '${vpn.engine == 'xray' ? 'Xray' : 'sing-box'} · ${vpn.activeServer?.name ?? ''}'
                      : s.t('ipDirect'),
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('tunnelDelay'),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _delay == null
                        ? s.t('notChecked')
                        : '${_delay} ${s.t('msUnit')}',
                    style: AppTextStyles.monoValue.copyWith(fontSize: 16),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: !connected || _delayBusy ? null : _measureDelay,
                  child: Text(s.t('measure')),
                ),
              ],
            ),
          ),
          SectionCard(
            title: s.t('connLive'),
            trailing: connected && vpn.engine == 'singbox'
                ? Text('${_connections.length}', style: AppTextStyles.monoValue)
                : null,
            child: !connected
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(s.t('connNeedConnect'), style: AppTextStyles.bodySecondary),
                  )
                : vpn.engine != 'singbox'
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Xray · SOCKS ${settings.settings.socksPort} / HTTP ${settings.settings.httpPort}',
                          style: AppTextStyles.bodySecondary,
                        ),
                      )
                    : _connections.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(s.t('connEmpty'), style: AppTextStyles.bodySecondary),
                          )
                        : Column(
                            children: [
                              for (final conn in _connections.take(60))
                                _ConnectionRow(conn: conn),
                            ],
                          ),
          ),
          Text(s.t('tcpPingNote'), style: AppTextStyles.bodySecondary),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.conn});

  final Map<String, dynamic> conn;

  @override
  Widget build(BuildContext context) {
    final metadata = conn['metadata'];
    final meta = metadata is Map
        ? metadata.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    final host = (meta['host'] ?? meta['destinationIP'] ?? '').toString();
    final network = (meta['network'] ?? '').toString().toUpperCase();
    final chains = conn['chains'];
    final chain = chains is List && chains.isNotEmpty
        ? chains.map((e) => e.toString()).join(' → ')
        : '';
    final rule = (conn['rule'] ?? '').toString();
    final up = (conn['upload'] as num?)?.toInt() ?? 0;
    final down = (conn['download'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.link_rounded, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.isEmpty ? '—' : host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (network.isNotEmpty) network,
                    if (chain.isNotEmpty) chain,
                    if (rule.isNotEmpty) rule,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('↑ ${FormatUtils.bytes(up)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.cyan, fontSize: 12)),
              Text('↓ ${FormatUtils.bytes(down)}', style: AppTextStyles.monoValue.copyWith(color: AppColors.success, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
