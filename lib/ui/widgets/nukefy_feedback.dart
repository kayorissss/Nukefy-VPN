import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/strings.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

void showNukefySnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppTextStyles.bodyRegular),
        backgroundColor: error ? context.palette.error.withValues(alpha: 0.9) : context.palette.surface,
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppTextStyles.headline),
      content: Text(body, style: context.palette.secondaryStyle),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.palette.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Error card you can actually send to someone: the text is selectable and a
/// copy button puts the whole message on the clipboard. Every raw error in the
/// app used to be a picture of a string.
class CopyableError extends StatelessWidget {
  const CopyableError({super.key, required this.message, this.strings, this.title});

  final String message;
  final S? strings;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withValues(alpha: .38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: AppTextStyles.bodyRegular.copyWith(fontWeight: FontWeight.w700, color: AppColors.error)),
                  const SizedBox(height: 4),
                ],
                SelectableText(
                  message,
                  style: AppTextStyles.bodySecondary.copyWith(color: AppColors.error),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: s?.t('copy') ?? 'Copy',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) {
                showNukefySnack(context, s?.t('copied') ?? 'Copied');
              }
            },
            icon: Icon(Icons.copy_rounded, size: 17, color: AppColors.error),
          ),
        ],
      ),
    );
  }
}
