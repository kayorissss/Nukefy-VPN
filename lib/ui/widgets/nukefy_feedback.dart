import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

void showNukefySnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: AppTextStyles.bodyRegular),
        backgroundColor: error ? const Color(0xFF2A1218) : AppColors.surface,
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
      content: Text(body, style: AppTextStyles.bodySecondary),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Turns internal engine error codes into text a human can act on.
/// Raw core output is kept (truncated) — errors are never hidden.
String humanVpnError(dynamic strings, String? raw) {
  final s = strings;
  final value = (raw ?? '').trim();
  if (value.isEmpty || value == 'core-failed' || value == 'core-exited') {
    return s.t('errCoreFailed');
  }
  if (value == 'CORE_MISSING') return s.t('errCoreMissing');
  if (value == 'XRAY_MISSING' || value.contains('xhttp-requires-xray')) {
    return s.t('errXrayMissing');
  }
  if (value == 'need-server') return s.t('errNeedServer');
  if (value.length > 320) return '${value.substring(0, 320)}…';
  return value;
}
