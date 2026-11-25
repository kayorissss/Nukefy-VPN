import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../l10n/strings.dart';

/// Latency indicator. Shows the number of milliseconds; when the server was
/// never pinged a quiet dot is drawn instead of dashes or crosses.
class PingBadge extends StatelessWidget {
  const PingBadge({
    super.key,
    required this.pingMs,
    this.compact = false,
    this.strings,
    this.tunnelOk,
  });

  final int? pingMs;
  final bool compact;
  final S? strings;

  /// Verdict of the last real tunnel probe for this server. `false` means the
  /// server answered on TCP but carried no traffic, in which case the latency
  /// is not shown at all — it is worse than useless.
  final bool? tunnelOk;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = p.pingColor(pingMs);
    if (tunnelOk == false) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 4 : 6),
        decoration: BoxDecoration(
          color: p.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.report_gmailerrorred_rounded, size: compact ? 12 : 14, color: p.warning),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(strings?.t('noTrafficShort') ?? 'no traffic',
                  style: AppTextStyles.bodySecondary.copyWith(color: p.warning, fontSize: 11.5)),
            ],
          ],
        ),
      );
    }
    if (pingMs == null) {
      // Never measured: a quiet dot, no invented number.
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.border),
      );
    }
    if (pingMs! < 0) {
      // The client tried this server and it did not answer: showing a latency
      // here would be a lie, so the row says so instead.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: compact ? 4 : 6),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off_rounded, size: compact ? 12 : 14, color: p.error),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(strings?.t('noAnswer') ?? 'No answer',
                  style: AppTextStyles.bodySecondary.copyWith(color: p.error, fontSize: 11.5)),
            ],
          ],
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tunnelOk == true) ...[
            // Confirmed by a real request through the tunnel, not by a socket.
            Icon(Icons.verified_rounded, size: compact ? 10 : 12, color: p.success),
            const SizedBox(width: 4),
          ],
          Text(
            '$pingMs ${Localizations.localeOf(context).languageCode == 'ru' ? 'мс' : 'ms'}',
            style: AppTextStyles.number.copyWith(color: color, fontSize: compact ? 11 : 12),
          ),
        ],
      ),
    );
  }
}
