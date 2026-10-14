import 'package:flutter/material.dart';

import '../../core/services/taskbar_progress.dart';
import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';
import '../widgets/nature_panel.dart';

/// Download dialog: text and numbers on the left, an animated
/// black-and-white nature scene on the right, and the progress bar with
/// percentages along the bottom. Wide enough to never look squeezed, and
/// mirrors progress to the OS taskbar icon while it is open.
class NukefyProgressDialog extends StatefulWidget {
  const NukefyProgressDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.strings,
    this.done = false,
    this.error,
    this.onCancel,
  });

  final String title;
  final String subtitle;
  final DownloadProgress? progress;
  final S strings;
  final bool done;
  final String? error;
  final VoidCallback? onCancel;

  @override
  State<NukefyProgressDialog> createState() => _NukefyProgressDialogState();
}

class _NukefyProgressDialogState extends State<NukefyProgressDialog> {
  @override
  void didUpdateWidget(covariant NukefyProgressDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    final fraction = widget.progress?.fraction;
    if (fraction != null && fraction != oldWidget.progress?.fraction) {
      TaskbarProgress.set(fraction);
    }
    if (widget.done || widget.error != null) {
      TaskbarProgress.clear();
    }
  }

  @override
  void dispose() {
    TaskbarProgress.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final progress = widget.progress;
    final fraction = widget.done ? 1.0 : (progress?.fraction ?? 0);
    final percent = (fraction * 100).clamp(0, 100).toStringAsFixed(0);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 560;
    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: NaturePanel(progress: fraction),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title, style: AppTextStyles.title),
                        const SizedBox(height: 6),
                        Text(widget.subtitle, style: AppTextStyles.bodySecondary),
                        const SizedBox(height: 18),
                        Text(
                          widget.done ? '100%' : '$percent%',
                          style: AppTextStyles.title.copyWith(fontSize: 34),
                        ),
                        const SizedBox(height: 10),
                        if (widget.error != null)
                          Text(
                            widget.error!,
                            style: AppTextStyles.bodySecondary
                                .copyWith(color: AppColors.error),
                          )
                        else if (progress != null) ...[
                          _Row(
                            label: strings.t('size'),
                            value:
                                '${FormatUtils.bytes(progress.received)} ${strings.t('of')} ${progress.total > 0 ? FormatUtils.bytes(progress.total) : '—'}',
                          ),
                          _Row(
                            label: strings.t('speed'),
                            value: FormatUtils.speed(progress.bps),
                          ),
                          _Row(
                            label: strings.t('remaining'),
                            value: FormatUtils.eta(progress.eta),
                          ),
                        ] else
                          Text(strings.t('downloading'),
                              style: AppTextStyles.bodySecondary),
                      ],
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 20),
                    SizedBox(width: 218, height: 218, child: panel),
                  ],
                ],
              ),
              if (!wide) ...[
                const SizedBox(height: 16),
                SizedBox(height: 120, child: panel),
              ],
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress == null && !widget.done ? null : fraction,
                  minHeight: 8,
                  backgroundColor:
                      Theme.of(context).dividerColor.withValues(alpha: 0.6),
                  color: widget.error != null
                      ? AppColors.error
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    widget.error != null
                        ? strings.t('error')
                        : widget.done
                            ? strings.t('ready')
                            : strings.t('downloading'),
                    style: AppTextStyles.bodySecondary,
                  ),
                  const Spacer(),
                  Text('$percent%', style: AppTextStyles.monoValue),
                ],
              ),
              if (widget.onCancel != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onCancel,
                    child: Text(strings.t('cancel')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: AppTextStyles.bodySecondary),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.monoValue),
          ),
        ],
      ),
    );
  }
}

/// Runs [task] behind the wide download dialog and returns its result
/// (or the error text as a String). Shared by core, Xray and app updates.
Future<Object?> showTaskProgressDialog<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required S strings,
  required Future<T> Function(void Function(DownloadProgress) onProgress) task,
}) {
  return showDialog<Object>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TaskProgressDialog<T>(
      title: title,
      subtitle: subtitle,
      strings: strings,
      task: task,
    ),
  );
}

class _TaskProgressDialog<T> extends StatefulWidget {
  const _TaskProgressDialog({
    required this.title,
    required this.subtitle,
    required this.strings,
    required this.task,
  });

  final String title;
  final String subtitle;
  final S strings;
  final Future<T> Function(void Function(DownloadProgress) onProgress) task;

  @override
  State<_TaskProgressDialog<T>> createState() => _TaskProgressDialogState<T>();
}

class _TaskProgressDialogState<T> extends State<_TaskProgressDialog<T>> {
  DownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    widget.task((next) {
      if (mounted) setState(() => _progress = next);
    }).then((value) {
      if (mounted) Navigator.pop(context, value);
    }).catchError((Object error) {
      if (mounted) Navigator.pop(context, '$error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return NukefyProgressDialog(
      title: widget.title,
      subtitle: widget.subtitle,
      progress: _progress,
      strings: widget.strings,
    );
  }
}
