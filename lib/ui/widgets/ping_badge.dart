import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class PingBadge extends StatelessWidget {
  const PingBadge({super.key, required this.pingMs, this.compact = false});

  final int? pingMs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.pingColor(pingMs);
    final text = pingMs == null
        ? '—'
        : pingMs! < 0
            ? '✕'
            : '${pingMs}ms';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: AppTextStyles.monoValue.copyWith(color: color, fontSize: 12),
      ),
    );
  }
}
