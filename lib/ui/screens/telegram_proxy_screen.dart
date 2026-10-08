import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/services/tg_ws_proxy_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_feedback.dart';
import '../widgets/responsive_sections.dart';

class TelegramProxyScreen extends StatelessWidget {
  const TelegramProxyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<TgWsProxyService>();
    final s = context.watch<SettingsProvider>().strings;
    return NukefyBackground(
      child: SafeArea(
        bottom: false,
        child: ResponsiveFrame(
          maxWidth: 1200,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFF229ED9).withValues(alpha: .16), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.send_rounded, color: Color(0xFF229ED9), size: 26)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.t('tgProxy'), style: AppTextStyles.title), const SizedBox(height: 4), Text(s.t('tgProxyHint'), style: context.palette.secondaryStyle)])),
                if (service.running) _StatusBadge(label: s.t('tgProxyRunning'), color: context.palette.success) else _StatusBadge(label: s.t('tgProxyStopped'), color: context.palette.textSecondary),
              ]),
              const SizedBox(height: 18),
              if (!Platform.isWindows)
                _MessageCard(icon: Icons.desktop_windows_rounded, message: s.t('tgProxyWindowsOnly'))
              else ...[
                LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 860
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _PowerCard(service: service, s: s)),
                              const SizedBox(width: 14),
                              Expanded(flex: 2, child: _ControlCard(service: service, s: s)),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            _PowerCard(service: service, s: s),
                            const SizedBox(height: 14),
                            _ControlCard(service: service, s: s),
                          ],
                        ),
                ),
                // The journal stays below the fold, and an empty journal is
                // not shown at all: a blank black box at the bottom read as a
                // broken screen rather than as "nothing happened yet".
                if (service.log.isNotEmpty) ...[
                  SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                  _LogCard(service: service, s: s),
                ],
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Big animated activation button: the proxy is either running or not, and
/// the primary action must be readable from across the room.
class _PowerCard extends StatelessWidget {
  const _PowerCard({required this.service, required this.s});
  final TgWsProxyService service;
  final S s;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final brand = const Color(0xFF229ED9);
    final color = service.running ? brand : p.accent;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: service.running ? brand.withValues(alpha: .55) : p.border),
        boxShadow: service.running ? [BoxShadow(color: brand.withValues(alpha: .25), blurRadius: 34, spreadRadius: 2)] : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PowerButton(service: service, s: s, color: color),
          const SizedBox(height: 14),
          Text(
            service.running ? s.t('tgProxyRunning') : s.t('tgProxyStopped'),
            style: AppTextStyles.status.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatefulWidget {
  const _PowerButton({required this.service, required this.s, required this.color});
  final TgWsProxyService service;
  final S s;
  final Color color;

  @override
  State<_PowerButton> createState() => _PowerButtonState();
}

class _PowerButtonState extends State<_PowerButton> {
  bool _busy = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.service.running) {
        await widget.service.stop();
      } else {
        await widget.service.start();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = widget.color;
    final installed = !widget.service.busy;
    return Column(
      children: [
        GestureDetector(
          onTap: _busy || widget.service.busy ? null : _toggle,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: .26), p.accent2.withValues(alpha: .16)],
              ),
              border: Border.all(color: color.withValues(alpha: .6), width: 1.5),
              boxShadow: [BoxShadow(color: color.withValues(alpha: .2), blurRadius: 36, spreadRadius: 2)],
            ),
            child: Center(
              child: _busy || widget.service.busy
                  ? SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3, color: color))
                  : Icon(widget.service.running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 56, color: color),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text('${widget.s.t('tgProxyError')}: $_error', style: TextStyle(color: p.error, fontSize: 11)),
        ],
        if (!installed) ...[
          const SizedBox(height: 10),
          Text(widget.s.t('tgProxyNotInstalled'), style: p.captionStyle),
        ],
      ],
    );
  }
}

class _ControlCard extends StatefulWidget {
  const _ControlCard({required this.service, required this.s});
  final TgWsProxyService service;
  final S s;

  @override
  State<_ControlCard> createState() => _ControlCardState();
}

class _ControlCardState extends State<_ControlCard> {
  bool _installed = false;
  bool _checking = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final file = await widget.service.binaryFile();
    if (!mounted) return;
    setState(() {
      _installed = file != null;
      _checking = false;
    });
  }

  Future<void> _download() async {
    if (_installed) {
      final confirmed = await confirmDialog(
        context,
        title: widget.s.t('tgProxyUpdateConfirmTitle'),
        body: widget.s.t('tgProxyUpdateConfirmBody'),
        confirm: widget.s.t('tgProxyUpdate'),
        cancel: widget.s.t('cancel'),
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _message = null);
    final wasRunning = widget.service.running;
    try {
      // Windows keeps an executable locked while it is running. Stop it
      // before replacing the file, then restore the user's previous state.
      if (wasRunning) await widget.service.stop();
      await widget.service.download(onProgress: (_) {});
      await _refresh();
      if (wasRunning) await widget.service.start();
      if (mounted) setState(() => _message = widget.s.t('tgProxyDownloaded'));
    } catch (error) {
      // A failed update must not leave an already installed proxy silently
      // stopped. The old file remains intact because download is atomic.
      if (wasRunning && !widget.service.running) {
        try { await widget.service.start(); } catch (_) {}
      }
      if (mounted) setState(() => _message = '${widget.s.t('tgProxyError')}: $error');
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDialog(
      context,
      title: widget.s.t('tgProxyDeleteTitle'),
      body: widget.s.t('tgProxyDeleteBody'),
      confirm: widget.s.t('delete'),
      cancel: widget.s.t('cancel'),
    );
    if (!confirmed || !mounted) return;
    await widget.service.deleteInstalled();
    await _refresh();
  }

  Future<void> _toggle() async {
    setState(() => _message = null);
    try {
      if (widget.service.running) {
        await widget.service.stop();
      } else {
        await widget.service.start();
      }
    } catch (error) {
      if (mounted) setState(() => _message = '${widget.s.t('tgProxyError')}: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.tune_rounded, color: p.accent), const SizedBox(width: 9), Expanded(child: Text(widget.s.t('tgProxyControl'), style: AppTextStyles.headline)), if (service.busy || _checking) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))]),
        const SizedBox(height: 8),
        Text(_installed ? widget.s.t('tgProxyInstalled') : widget.s.t('tgProxyNotInstalled'), style: p.secondaryStyle),
        if (_message != null) ...[const SizedBox(height: 10), SelectableText(_message!, style: p.secondaryStyle)],
        if (service.lastError != null && service.busy == false) ...[
          const SizedBox(height: 10),
          SelectableText('${widget.s.t('tgProxyError')}: ${service.lastError}', style: TextStyle(color: p.error, fontSize: 12)),
        ],
        if (service.progress != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: service.progress!.fraction),
          const SizedBox(height: 6),
          Row(children: [Expanded(child: Text('${widget.s.t('tgProxyProgress')}: ${FormatUtils.bytes(service.progress!.received)} / ${FormatUtils.bytes(service.progress!.total)}', style: p.captionStyle)), if (service.busy) TextButton(onPressed: service.cancelDownload, child: Text(widget.s.t('cancel')))]),
        ],
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!_installed)
            FilledButton.icon(onPressed: service.busy ? null : _download, icon: service.busy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download_rounded), label: Text(widget.s.t('tgProxyDownload')))
          else
            FilledButton.icon(onPressed: service.busy ? null : _toggle, icon: Icon(service.running ? Icons.stop_rounded : Icons.play_arrow_rounded), label: Text(service.running ? widget.s.t('tgProxyStop') : widget.s.t('tgProxyStart'))),
          if (_installed) OutlinedButton.icon(onPressed: service.busy ? null : _download, icon: const Icon(Icons.system_update_alt_rounded), label: Text(widget.s.t('tgProxyUpdate'))),
          if (_installed) OutlinedButton.icon(onPressed: service.busy ? null : _delete, icon: const Icon(Icons.delete_outline_rounded), label: Text(widget.s.t('delete'))),
          OutlinedButton.icon(onPressed: service.openLog, icon: const Icon(Icons.folder_open_rounded), label: Text(widget.s.t('tgProxyOpenLog'))),
        ]),
        const SizedBox(height: 12),
        Text(widget.s.t('tgProxyIntegrity'), style: p.captionStyle),
      ]),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.service, required this.s});
  final TgWsProxyService service;
  final S s;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lines = service.log;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.article_outlined, color: p.accent), const SizedBox(width: 9), Expanded(child: Text(s.t('tgProxyLogs'), style: AppTextStyles.headline)), Text('${lines.length}', style: p.captionStyle), IconButton(onPressed: lines.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: lines.join('\n'))), tooltip: s.t('copy'), icon: const Icon(Icons.copy_rounded, size: 18))]),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 58), child: Center(child: Text(s.t('tgProxyNoLogs'), style: p.secondaryStyle)))
        else
          Container(width: double.infinity, constraints: const BoxConstraints(maxHeight: 340), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: p.background.withValues(alpha: .7), borderRadius: BorderRadius.circular(8)), child: SingleChildScrollView(reverse: true, child: SelectableText(lines.join('\n'), style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, height: 1.45, color: p.textSecondary)))),
      ]),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: context.palette.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: context.palette.border)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: context.palette.accent), const SizedBox(width: 12), Expanded(child: Text(message, style: context.palette.secondaryStyle))]));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 7), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12))]));
}
