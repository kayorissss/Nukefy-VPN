import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_colors.dart';

/// The app mark. Plain image with a soft glow — no frames.
class NukefyLogo extends StatelessWidget {
  const NukefyLogo({super.key, this.size = 36, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final iconName = context.watch<SettingsProvider>().settings.appIcon;
    final image = _image(p, iconName);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.18),
                  blurRadius: size * 0.6,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      // Carbon keeps the built-in default mark neutral, but an explicitly
      // chosen icon variant must remain visibly chosen (pink, emerald, etc.).
      child: _isMonochrome(p) && iconName == 'default'
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                .2126, .7152, .0722, 0, 0,
                .2126, .7152, .0722, 0, 0,
                .2126, .7152, .0722, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: image,
            )
          : image,
    );
  }

  bool _isMonochrome(NukefyPalette p) {
    final color = p.accent;
    // Use the non-deprecated channel accessors introduced with Flutter's
    // colour API. Carbon's accent is deliberately equal on all channels.
    return color.r == color.g && color.g == color.b;
  }

  Widget _image(NukefyPalette p, String icon) {
    final asset = icon == 'default' ? 'assets/icons/app_icon.png' : 'assets/icons/app_icon_$icon.png';
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ColoredBox(
        color: p.background,
        child: Center(
          child: Text(
            'N',
            style: TextStyle(
              color: p.accent,
              fontFamily: 'Unbounded',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
