import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/update_service.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../widgets/nukefy_background.dart';
import '../widgets/nukefy_logo.dart';

enum _Phase { offer, downloading, done, failed }

/// Full-screen update flow: what's new → animated download → install.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, required this.info});

  final UpdateInfo info;

  static Future<void> open(BuildContext context, UpdateInfo info) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => UpdateScreen(info: info),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  _Phase _phase = _Phase.offer;
  DownloadProgress? _progress;
  File? _file;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
    });
    try {
      final file = await UpdateService().download(widget.info, onProgress: (next) {
        if (mounted) setState(() => _progress = next);
      });
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _Phase.done;
      });
      await _install();
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = '$error';
      });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;
    if (Platform.isAndroid && file.path.endsWith('.apk')) {
      await VpnPlatform().installApk(file.path);
    } else {
      await VpnPlatform().revealFile(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>().strings;
    final p = context.palette;
    final info = widget.info;
    final busy = _phase == _Phase.downloading;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: NukefyBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: IconButton(
                          onPressed: busy ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      const Spacer(),
                      _Hero(phase: _phase, progress: _progress),
                      const SizedBox(height: 28),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Column(
                          key: ValueKey(_phase),
                          children: [
                            Text(
                              switch (_phase) {
                                _Phase.offer => s.t('updateAvailable'),
                                _Phase.downloading => s.t('downloading'),
                                _Phase.done => s.t('updateReady'),
                                _Phase.failed => s.t('updateFailed'),
                              },
                              textAlign: TextAlign.center,
                              style: AppTextStyles.title,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${AppConstants.version}  →  ${info.version}',
                              style: AppTextStyles.number.copyWith(color: p.accent, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_phase == _Phase.offer)
                        Flexible(
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: p.card,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: p.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.t('whatsNew').toUpperCase(), style: AppTextStyles.section.copyWith(color: p.textSecondary)),
                                const SizedBox(height: 8),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: Text(
                                      info.notes.trim().isEmpty ? '—' : info.notes.trim(),
                                      style: AppTextStyles.bodySecondary.copyWith(color: p.text, height: 1.45),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.06),
                      if (_phase == _Phase.downloading && _progress != null)
                        Column(
                          children: [
                            Text(
                              '${FormatUtils.bytes(_progress!.received)} ${s.t('of')} ${_progress!.total > 0 ? FormatUtils.bytes(_progress!.total) : '—'}',
                              style: AppTextStyles.number.copyWith(fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.t('speed')} ${FormatUtils.speed(_progress!.bps)} · ${s.t('remaining')} ${FormatUtils.eta(_progress!.eta)}',
                              style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary),
                            ),
                          ],
                        ),
                      if (_phase == _Phase.failed)
                        Text(
                          _error ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                        ),
                      if (_phase == _Phase.done)
                        Text(
                          Platform.isAndroid ? s.t('updateInstallHint') : s.t('updateRevealHint'),
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary),
                        ),
                      const Spacer(),
                      _Actions(
                        phase: _phase,
                        hasAsset: info.hasAsset,
                        onDownload: _download,
                        onInstall: _install,
                        onOpenRelease: () => launchUrl(Uri.parse(info.htmlUrl), mode: LaunchMode.externalApplication),
                        onLater: () => Navigator.pop(context),
                        strings: s,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.phase, required this.progress});

  final _Phase phase;
  final DownloadProgress? progress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fraction = progress?.fraction ?? 0;
    final indeterminate = phase == _Phase.downloading && (progress == null || progress!.total <= 0);
    final ringColor = switch (phase) {
      _Phase.done => p.success,
      _Phase.failed => AppColors.error,
      _ => p.accent,
    };
    Widget ring = SizedBox(
      width: 196,
      height: 196,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: ringColor.withValues(alpha: 0.28), blurRadius: 48, spreadRadius: 4)],
            ),
          ),
          if (phase == _Phase.downloading || phase == _Phase.done)
            SizedBox(
              width: 196,
              height: 196,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: phase == _Phase.done ? 1 : fraction),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => CircularProgressIndicator(
                  value: indeterminate ? null : value,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: p.border,
                  color: ringColor,
                ),
              ),
            ),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.card,
              border: Border.all(color: p.border),
            ),
            child: Center(
              child: switch (phase) {
                _Phase.downloading => Text(
                    indeterminate ? '…' : '${(fraction * 100).round()}%',
                    style: AppTextStyles.number.copyWith(fontSize: 30, color: p.accent),
                  ),
                _Phase.done => Icon(Icons.check_rounded, size: 64, color: p.success),
                _Phase.failed => const Icon(Icons.error_outline_rounded, size: 60, color: AppColors.error),
                _Phase.offer => const NukefyLogo(size: 96),
              },
            ),
          ),
        ],
      ),
    );
    if (phase == _Phase.offer) {
      ring = ring
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(begin: -6, end: 6, duration: 2200.ms, curve: Curves.easeInOut);
    } else if (phase == _Phase.done) {
      ring = ring.animate().scale(begin: const Offset(0.9, 0.9), curve: Curves.elasticOut, duration: 700.ms);
    }
    return ring;
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.phase,
    required this.hasAsset,
    required this.onDownload,
    required this.onInstall,
    required this.onOpenRelease,
    required this.onLater,
    required this.strings,
  });

  final _Phase phase;
  final bool hasAsset;
  final VoidCallback onDownload;
  final VoidCallback onInstall;
  final VoidCallback onOpenRelease;
  final VoidCallback onLater;
  final dynamic strings;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    switch (phase) {
      case _Phase.offer:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: hasAsset ? onDownload : onOpenRelease,
                icon: Icon(hasAsset ? Icons.download_rounded : Icons.open_in_new_rounded),
                label: Text(hasAsset ? s.t('download') : s.t('openRelease')),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onLater, child: Text(s.t('later'))),
          ],
        );
      case _Phase.downloading:
        return const SizedBox(height: 60);
      case _Phase.done:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onInstall,
                icon: const Icon(Icons.install_mobile_rounded),
                label: Text(Platform.isAndroid ? s.t('install') : s.t('openFolder')),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onLater, child: Text(s.t('close'))),
          ],
        );
      case _Phase.failed:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(s.t('retry')),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onOpenRelease, child: Text(s.t('openRelease'))),
          ],
        );
    }
  }
}
