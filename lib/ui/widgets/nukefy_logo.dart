import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The app mark. Plain image with a soft glow — no frames.
class NukefyLogo extends StatelessWidget {
  const NukefyLogo({super.key, this.size = 36, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
      child: _isMonochrome(p)
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                .2126, .7152, .0722, 0, 0,
                .2126, .7152, .0722, 0, 0,
                .2126, .7152, .0722, 0, 0,
                0, 0, 0, 1, 0,
              ]),
              child: _image(p),
            )
          : _image(p),
    );
  }

  bool _isMonochrome(NukefyPalette p) => p.accent.red == p.accent.green && p.accent.green == p.accent.blue;

  Widget _image(NukefyPalette p) => Image.asset(
        'assets/icons/app_icon.png',
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
