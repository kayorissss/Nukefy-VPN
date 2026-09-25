import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Latency indicator. Shows the number of milliseconds; when the server was
/// never pinged a quiet dot is drawn instead of dashes or crosses.
class PingBadge extends StatelessWidget {
  const PingBadge({super.key, required this.pingMs, this.compact = false});

  final int? pingMs;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.pingColor(pingMs);
    if (pingMs == null || pingMs! < 0) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pingMs == null ? p.border : AppColors.error.withValues(alpha: 0.7),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$pingMs ms',
        style: AppTextStyles.number.copyWith(color: color, fontSize: compact ? 11 : 12),
      ),
    );
  }
}
