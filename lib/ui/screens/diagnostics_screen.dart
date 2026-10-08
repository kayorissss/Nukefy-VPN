import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

import '../../core/models/server_model.dart';
import '../../core/models/vpn_status.dart';
import '../../core/providers/servers_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/connectivity_probe.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/services/zapret_service.dart';
import '../../core/services/connection_analyzer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/section_card.dart';

/// "Почему не работает" in one screen: local machine checks, a through-tunnel
/// probe and a server sweep that answers the question people actually have —
/// which server lets YouTube load.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
      );

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _ServerScanResult {
  _ServerScanResult(this.server);
  final ServerModel server;
  bool? youtube;
  int latency = -1;
  String? error;
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final List<AnalyzerCheck> _checks = [];
  bool _running = false;
  bool _scanning = false;
  bool _cancelScan = false;
  final List<_ServerScanResult> _scan = [];
  int _scanDone = 0;
  int _scanTotal = 0;
  String _scanCurrent = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _checks.clear();
    });
    final settings = context.read<SettingsProvider>().settings;
    final vpn = context.read<VpnProvider>();
    final ports = vpn.activePorts;
    final connected = vpn.status == VpnStatus.connected;
    // Always use a local ingress for connected checks. The app's own desktop
    // process is deliberately routed direct by sing-box, so a plain HTTP probe
    // would otherwise measure the wrong network path.
    final probePort = settings.localProxyEnabled ? ports?.http : ports?.probe;
    final proxyPort = connected ? probePort : null;

    Future<void> add(Future<AnalyzerCheck> Function() run) async {
      final check = await run();
      if (!mounted) return;
      setState(() => _checks.add(check));
    }

    await add(ConnectionAnalyzer.checkClock);
    await add(ConnectionAnalyzer.checkSystemProxy);
    await add(ConnectionAnalyzer.checkCertificateInspectors);
    await add(ConnectionAnalyzer.checkVpnConflicts);
    await add(ConnectionAnalyzer.checkZapretStack);
    await add(ConnectionAnalyzer.checkTcpTimestamps);
    await add(ConnectionAnalyzer.checkDns);
    final (directCheck, directIp) = await ConnectionAnalyzer.checkDirectInternet();
    if (mounted) setState(() => _checks.add(directCheck));
    if (connected && proxyPort != null) {
      await add(() => ConnectionAnalyzer.checkTunnelExit(httpProxyPort: proxyPort, directIp: directIp));
    } else {
      if (mounted) {
        setState(() => _checks.add(AnalyzerCheck(
              id: 'tunnel',
              level: CheckLevel.info,
              title: 'Трафик через VPN',
              detail: connected
                  ? 'VPN подключён, но локальный порт проверки недоступен'
                  : 'VPN не подключён — проверка туннеля пропущена',
              hint: connected
                  ? 'Переподключитесь через Nukefy, чтобы приложение могло провести запрос через туннель.'
                  : 'Нажмите «Запустить» на главной, дождитесь состояния «Подключено» и повторите проверку.',
            )));
      }
    }
    if (connected && proxyPort == null) {
      if (mounted) {
        setState(() => _checks.add(AnalyzerCheck(
              id: 'targets',
              level: CheckLevel.info,
              title: 'Доступность YouTube, Discord и Telegram',
              detail: 'Нельзя проверить через VPN: нет локального порта проверки. Переподключитесь из приложения.',
            )));
      }
    } else {
      final (targetChecks, _) = await ConnectionAnalyzer.checkTargets(httpProxyPort: connected ? proxyPort : null);
      if (mounted) setState(() => _checks.addAll(targetChecks));
    }
    if (!mounted) return;
    setState(() => _running = false);
    // Refresh the banner state on the home screen with these results.
    if (connected) await vpn.verifyTrafficNow();
  }

  String? _fixing;
  String? _fixError;

  /// Safe, reversible remedies offered directly on an analyzer row. Anything
  /// that would touch another program's configuration only *stops ours* or
  /// explains what the user should do themselves.
  Future<void> _applyFix(AnalyzerCheck check) async {
    final s = context.read<SettingsProvider>().strings;
    final id = check.fixId;
    if (id == null) return;
    setState(() { _fixing = id; _fixError = null; });
    String result = 'ok';
    try {
      final vpn = context.read<VpnProvider>();
      switch (id) {
        case 'proxy-off':
          final confirmed = await confirmDialog(
            context,
            title: s.t('proxyDisableTitle'),
            body: s.t('proxyDisableBody'),
            confirm: s.t('proxyDisable'),
            cancel: s.t('cancel'),
          );
          if (!confirmed || !mounted) {
            if (mounted) setState(() => _fixing = null);
            return;
          }
          result = await VpnPlatform().disableSystemProxy();
          break;
        case 'proxy-restore':
          final confirmed = await confirmDialog(
            context,
            title: s.t('proxyRestoreTitle'),
            body: s.t('proxyRestoreBody'),
            confirm: s.t('proxyRestore'),
            cancel: s.t('cancel'),
          );
          if (!confirmed || !mounted) {
            if (mounted) setState(() => _fixing = null);
            return;
          }
          result = await VpnPlatform().restoreSystemProxy();
          break;
        case 'zapret-stop':
          await ZapretService.instance.stop(includeService: true);
          result = 'ok';
          break;
        case 'tcp-timestamps-enable':
          final confirmed = await confirmDialog(
            context,
            title: s.t('tcpTimestampsTitle'),
            body: s.t('tcpTimestampsEnableBody'),
            confirm: s.t('tcpTimestampsEnable'),
            cancel: s.t('cancel'),
          );
          if (!confirmed || !mounted) {
            if (mounted) setState(() => _fixing = null);
            return;
          }
          result = await VpnPlatform().enableFlowsealTcpTimestamps();
          break;
        case 'tcp-timestamps-restore':
          final confirmed = await confirmDialog(
            context,
            title: s.t('tcpTimestampsRestoreTitle'),
            body: s.t('tcpTimestampsRestoreBody'),
            confirm: s.t('tcpTimestampsRestore'),
            cancel: s.t('cancel'),
          );
          if (!confirmed || !mounted) {
            if (mounted) setState(() => _fixing = null);
            return;
          }
          result = await VpnPlatform().restoreFlowsealTcpTimestamps();
          break;
        case 'dns-apply':
          final confirmed = await confirmDialog(
            context,
            title: s.t('dnsSystemApplyTitle'),
            body: s.t('dnsSystemApplyBody'),
            confirm: s.t('dnsSystemApply'),
            cancel: s.t('cancel'),
          );
          if (!confirmed || !mounted) {
            if (mounted) setState(() => _fixing = null);
            return;
          }
          result = await VpnPlatform().applyCloudflareDns();
          break;
        case 'clock-open':
          await url_launcher.launchUrl(Uri.parse('ms-settings:dateandtime'));
          result = 'ok';
          break;
        default:
          result = 'unknown-fix';
      }
      if (vpn.status == VpnStatus.connected) await vpn.verifyTrafficNow();
    } catch (error) {
      result = '$error';
    }
    if (!mounted) return;
    setState(() => _fixing = null);
    final succeeded = result == 'ok' || const [
      'Current-user proxy disabled',
      'Previous current-user proxy settings restored',
      'Cloudflare DNS set',
      'Previous DNS restored',
      'TCP timestamps enabled',
      'TCP timestamps restored',
    ].any(result.startsWith);
    setState(() => _fixError = succeeded ? null : result);
    showNukefySnack(context, '${s.t('diagFixDone')}: $result', error: !succeeded);
    // Re-run so the row turns green only when it really is fixed.
    await _run();
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: ConnectionAnalyzer.report(_checks)));
    if (mounted) showNukefySnack(context, context.read<SettingsProvider>().strings.t('copied'));
  }

  /// Connects to each candidate in turn and asks whether YouTube loads through
  /// it. Slow by nature (a real handshake per server), so it is cancellable
  /// and capped: the point is to find a working server quickly, not to test a
  /// thousand entries.
  Future<void> _scanServers() async {
    if (_scanning) return;
    final servers = context.read<ServersProvider>();
    final vpn = context.read<VpnProvider>();
    final candidates = servers.servers.where((s) => !s.isInformational).take(12).toList();
    if (candidates.isEmpty) {
      showNukefySnack(context, context.read<SettingsProvider>().strings.t('srvScanEmpty'));
      return;
    }
    setState(() {
      _scanning = true;
      _cancelScan = false;
      _scan
        ..clear()
        ..addAll(candidates.map(_ServerScanResult.new));
      _scanDone = 0;
      _scanTotal = candidates.length;
      _scanCurrent = '';
    });
    for (final result in _scan) {
      if (_cancelScan || !mounted) break;
      setState(() => _scanCurrent = result.server.name);
      try {
        await vpn.connect(result.server).timeout(const Duration(seconds: 25));
      } catch (_) {}
      if (vpn.status != VpnStatus.connected) {
        result.error = 'не подключился';
        setState(() => _scanDone++);
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final ports = vpn.activePorts;
      final tun = context.read<SettingsProvider>().settings.tunEnabled;
      final proxyPort = !tun && ports != null ? ports.http : null;
      final probe = await ConnectivityProbe.http(
        ConnectivityProbe.defaultTargets.first.url,
        httpProxyPort: proxyPort,
        timeout: const Duration(seconds: 10),
      );
      result
        ..youtube = probe.ok
        ..latency = probe.ms;
      await vpn.disconnect();
      if (!mounted) break;
      setState(() => _scanDone++);
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanCurrent = '';
    });
    _scan.sort((a, b) {
      final aScore = (a.youtube == true ? 0 : 1) * 1000 + (a.latency < 0 ? 999 : a.latency);
      final bScore = (b.youtube == true ? 0 : 1) * 1000 + (b.latency < 0 ? 999 : b.latency);
      return aScore.compareTo(bScore);
    });
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<SettingsProvider>().strings;
    final p = context.palette;
    final content = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          SectionCard(
            title: s.t('diagTitle'),
            icon: Icons.health_and_safety_outlined,
            trailing: _running
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : NukefyActionButton(label: s.t('diagRun'), icon: Icons.play_arrow_rounded, onPressed: _run),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('diagHint'), style: p.secondaryStyle),
                const SizedBox(height: 8),
                for (final check in _checks)
                  _CheckRow(check: check, onFix: _applyFix, fixing: _fixing == check.fixId),
                if (_running && _checks.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator(minHeight: 3)),
              ],
            ),
          ),
          if (_fixError != null) ...[
            const SizedBox(height: 12),
            CopyableError(message: _fixError!, strings: s, title: s.t('diagFixError')),
          ],
          const SizedBox(height: 4),
          SectionCard(
            title: s.t('diagScanTitle'),
            icon: Icons.travel_explore_rounded,
            trailing: _scanning
                ? NukefyActionButton(label: s.t('cancel'), onPressed: () => setState(() => _cancelScan = true))
                : NukefyActionButton(label: s.t('diagScanRun'), icon: Icons.play_arrow_rounded, onPressed: _scanServers),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('diagScanHint'), style: p.secondaryStyle),
                if (_scanTotal > 0) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: _scanTotal == 0 ? null : _scanDone / _scanTotal, minHeight: 4),
                  const SizedBox(height: 6),
                  Text(
                    _scanning ? '$_scanDone / $_scanTotal · $_scanCurrent' : '$_scanDone / $_scanTotal',
                    style: p.captionStyle,
                  ),
                ],
                const SizedBox(height: 6),
                for (final result in _scan) _ScanRow(result: result, strings: s),
              ],
            ),
          ),
        ],
    );
    if (Navigator.of(context).canPop()) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(s.t('diagTitle')),
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            IconButton(tooltip: s.t('diagCopy'), onPressed: _checks.isEmpty ? null : _copyReport, icon: const Icon(Icons.copy_rounded)),
            const SizedBox(width: 6),
          ],
        ),
        body: SafeArea(bottom: false, child: content),
      );
    }
    return SafeArea(bottom: false, child: content);
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, this.onFix, this.fixing = false});

  final AnalyzerCheck check;

  /// Runs the safe remedy offered for this finding, when one exists.
  final Future<void> Function(AnalyzerCheck check)? onFix;
  final bool fixing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = switch (check.level) {
      CheckLevel.ok => (Icons.check_circle_rounded, AppColors.success),
      CheckLevel.warn => (Icons.error_outline_rounded, const Color(0xFFE8B23A)),
      CheckLevel.error => (Icons.cancel_rounded, AppColors.error),
      CheckLevel.info => (Icons.info_outline_rounded, p.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title, style: AppTextStyles.bodyRegular.copyWith(color: p.text).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(check.detail, style: p.secondaryStyle),
                if (check.hint != null) ...[
                  const SizedBox(height: 4),
                  SelectableText(check.hint!, style: p.captionStyle.copyWith(color: p.accent.withValues(alpha: .9))),
                ],
                // Right on the row: what can be fixed gets a button, and the
                // button says what it will do before it is pressed.
                if (check.fixId != null && onFix != null) ...[
                  const SizedBox(height: 8),
                  if (check.fixHint != null) ...[
                    Text(check.fixHint!, style: p.captionStyle.copyWith(color: p.textDisabled)),
                    const SizedBox(height: 6),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: NukefyActionButton(
                      icon: fixing ? Icons.hourglass_top_rounded : Icons.build_circle_outlined,
                      label: fixing ? context.read<SettingsProvider>().strings.t('diagFixing') : (check.fixLabel ?? ''),
                      onPressed: fixing ? null : () => onFix!(check),
                      filled: true,
                    ),
                  ),
                ],
                if (check.detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: '${check.title}: ${check.detail}${check.hint == null ? '' : '\n${check.hint}'}',
                        ));
                        if (context.mounted) {
                          showNukefySnack(context, context.read<SettingsProvider>().strings.t('copied'));
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 15),
                      label: Text(context.read<SettingsProvider>().strings.t('copy'), style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.result, required this.strings});

  final _ServerScanResult result;
  final S strings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color, verdict) = result.youtube == null
        ? (Icons.hourglass_empty_rounded, p.textSecondary, result.error ?? '…')
        : result.youtube == true
            ? (Icons.check_circle_rounded, AppColors.success, '${strings.t('diagScanOk')} · ${result.latency} мс')
            : (Icons.cancel_rounded, AppColors.error, strings.t('diagScanFail'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(result.server.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyRegular.copyWith(color: p.text).copyWith(fontWeight: FontWeight.w600)),
          ),
          Text(verdict, style: p.captionStyle),
          const SizedBox(width: 8),
          if (result.youtube == true)
            NukefyActionButton(
              label: strings.t('diagScanUse'),
              filled: false,
              onPressed: () async {
                final vpn = context.read<VpnProvider>();
                await vpn.connect(result.server);
              },
            ),
        ],
      ),
    );
  }
}
