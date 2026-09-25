import 'package:flutter/material.dart';

import '../../core/services/vpn_platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/format_utils.dart';
import '../../l10n/strings.dart';

class NukefyProgressDialog extends StatelessWidget {
  const NukefyProgressDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.strings,
    this.done = false,
    this.error,
  });

  final String title;
  final String subtitle;
  final DownloadProgress? progress;
  final S strings;
  final bool done;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction ?? 0;
    final percent = (fraction * 100).clamp(0, 100).toStringAsFixed(0);
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.headline),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center, style: AppTextStyles.bodySecondary),
            const SizedBox(height: 18),
            SizedBox(
              width: 132,
              height: 132,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: CircularProgressIndicator(
                      value: progress == null || (progress!.total <= 0 && !done) ? null : fraction,
                      strokeWidth: 7,
                      backgroundColor: context.palette.border,
                      color: done ? context.palette.success : context.palette.accent,
                    ),
                  ),
                  Text(
                    done ? '100%' : '$percent%',
                    style: AppTextStyles.number.copyWith(fontSize: 22, color: context.palette.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Text(error!, style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error))
            else if (progress != null) ...[
              Text(
                '${FormatUtils.bytes(progress!.received)} ${strings.t('of')} ${progress!.total > 0 ? FormatUtils.bytes(progress!.total) : '—'}',
                style: AppTextStyles.monoValue,
              ),
              const SizedBox(height: 4),
              Text(
                '${strings.t('speed')} ${FormatUtils.speed(progress!.bps)} · ${strings.t('remaining')} ${FormatUtils.eta(progress!.eta)}',
                style: AppTextStyles.bodySecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
