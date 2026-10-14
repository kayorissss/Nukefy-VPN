import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/nav_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/vpn_provider.dart';
import '../../core/services/notification_hub.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';

/// Wraps the whole app: VPN errors and warnings land here as toasts in the
/// top-right corner instead of sitting as raw text under the connect
/// button. A toast can be closed, and everything ever shown stays behind
/// the bell until the user clears it.
class NotificationOverlay extends StatefulWidget {
  const NotificationOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  final _hub = NotificationHub.instance;
  AppNotice? _toast;
  Timer? _timer;
  String? _lastError;
  String? _lastConflict;
  VpnProvider? _vpn;

  @override
  void initState() {
    super.initState();
    _hub.addListener(_onHub);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vpn = context.read<VpnProvider>();
    if (_vpn != vpn) {
      _vpn?.removeListener(_onVpn);
      _vpn = vpn;
      _vpn!.addListener(_onVpn);
    }
  }

  @override
  void dispose() {
    _hub.removeListener(_onHub);
    _vpn?.removeListener(_onVpn);
    _timer?.cancel();
    super.dispose();
  }

  void _onHub() {
    if (!mounted) return;
    final latest = _hub.items.isEmpty ? null : _hub.items.first;
    if (latest != null && latest.id != _toast?.id) {
      _timer?.cancel();
      setState(() => _toast = latest);
      _timer = Timer(const Duration(seconds: 7), () {
        if (mounted) setState(() => _toast = null);
      });
    }
    setState(() {});
  }

  /// VPN state changes are the main notice source: a fresh error or a fresh
  /// conflict warning becomes a toast + a history entry exactly once.
  void _onVpn() {
    final vpn = _vpn;
    if (vpn == null || !mounted) return;
    final s = context.read<SettingsProvider>().strings;
    final error = vpn.errorMessage;
    if (error != null && error != _lastError) {
      _hub.show(title: s.t('connectionError'), body: friendlyVpnError(s, error), error: true, destination: NavDestination.home);
    }
    _lastError = error;
    final conflict = vpn.conflictNotice;
    if (conflict != null && conflict != _lastConflict) {
      _hub.show(title: s.t('conflictWarn'), body: conflict, destination: NavDestination.home);
    }
    _lastConflict = conflict;
  }

  Future<void> _openHistory() async {
    _hub.markRead();
    final s = context.read<SettingsProvider>().strings;
    final nav = context.read<NavProvider>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
        final p = dialogContext.palette;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.t('notifications'), style: AppTextStyles.headline)),
                      if (_hub.items.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            _hub.clear();
                            Navigator.pop(dialogContext);
                          },
                          child: Text(s.t('notifClear')),
                        ),
                      IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_hub.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(s.t('notifEmpty'), textAlign: TextAlign.center, style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary)),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _hub.items.length,
                        separatorBuilder: (_, _) => Divider(height: 1, color: p.border),
                        itemBuilder: (context, index) {
                          final notice = _hub.items[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            leading: Icon(
                              notice.error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                              color: notice.error ? p.error : p.accent,
                              size: 20,
                            ),
                            title: Text(notice.title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5)),
                            subtitle: Text(
                              '${notice.body}\n${FormatUtils.timeAgo(notice.time, ru: FormatUtils.russian)}',
                              style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16),
                              onPressed: () => setDialogState(() => _hub.dismiss(notice)),
                            ),
                            onTap: notice.destination == null
                                ? null
                                : () {
                                    nav.go(notice.destination!);
                                    Navigator.pop(dialogContext);
                                  },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final toast = _toast;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: desktop ? 50 : 10,
          right: 14,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _BellButton(unread: _hub.unread, onTap: _openHistory),
                if (toast != null) ...[
                  const SizedBox(height: 10),
                  _ToastCard(
                    notice: toast,
                    onClose: () {
                      _timer?.cancel();
                      setState(() => _toast = null);
                    },
                    onTap: toast.destination == null
                        ? null
                        : () {
                            context.read<NavProvider>().go(toast.destination!);
                            _hub.markRead();
                            setState(() => _toast = null);
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.card,
      shape: CircleBorder(side: BorderSide(color: p.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_none_rounded, size: 20, color: p.textSecondary),
              if (unread > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: p.error, borderRadius: BorderRadius.circular(8)),
                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.notice, required this.onClose, this.onTap});

  final AppNotice notice;
  final VoidCallback onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: notice.error ? p.error.withValues(alpha: .45) : p.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(notice.error ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                  size: 19, color: notice.error ? p.error : p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notice.title, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text(notice.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 15, color: p.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Human text for the machine codes VpnProvider reports, so a toast never
/// shows a raw ALL_CAPS code to the user. (Lives here, not on the home
/// screen: the home screen no longer renders errors inline at all.)
String friendlyVpnError(S s, String raw) {
if (raw == 'CORE_MISSING') return s.t('coreMissing');
    if (raw == 'LIBBOX_MISSING') return s.t('libboxMissing');
    if (raw == 'information-entry') return s.t('informationEntry');
    if (raw == 'need-server') return s.t('needServer');
    if (raw == 'XHTTP_UNSUPPORTED') return s.t('xhttpUnsupported');
    if (raw == 'CORE_PROTOCOL_UNSUPPORTED') return s.t('coreProtocolUnsupported');
    if (raw == 'CORE_MIERU_UNSUPPORTED') return s.t('coreMieruUnsupported');
    if (raw == 'CORE_OUTBOUND_MISSING') return s.t('coreOutboundMissing');
    if (raw == 'CORE_ENDPOINT_MISSING') return s.t('coreEndpointMissing');
    if (raw == 'NO_TRAFFIC_MODE') return s.t('noTrafficMode');
    if (raw == 'XRAY_TRANSPORT_REQUIRED') return s.t('xrayTransportRequired');
    if (raw == 'XRAY_CORE_MISSING') return s.t('xrayNotInstalled');
    if (raw == 'XRAY_PLATFORM_UNSUPPORTED') return s.t('xrayPlatformUnsupported');
    if (raw == 'XRAY_UNSUPPORTED_PROTOCOL') return s.t('xrayUnsupportedProtocol');
    if (raw == 'XRAY_FRONTEND_MISSING') return s.t('xrayFrontendMissing');
    if (raw == 'XRAY_NO_TRAFFIC_MODE') return s.t('xrayNoTrafficMode');
    if (raw.startsWith('XRAY_')) return '${s.t('xrayCore')}: $raw';
    if (raw.startsWith('NO_TRAFFIC:')) return '${s.t('noTraffic')}\n${raw.substring(11)}';
    if (raw == 'NO_TRAFFIC_TARGETS') return s.t('noTrafficTargets');
    if (raw == 'TRAFFIC_PROBE_UNAVAILABLE') return s.t('trafficProbeUnavailable');
    if (raw.contains('Permission denied') && raw.contains('sing-box')) return s.t('libboxMissing');
    if (raw.contains('legacy inbound fields')) return s.t('coreOutdatedConfig');
    // Strip ANSI colour codes and the timestamp prefix from core logs.
    final clean = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').replaceAll(RegExp(r'^\S*FATAL\S*\[\d+\]\s*'), '');
    return clean.length > 260 ? '${clean.substring(0, 260)}…' : clean;
}
