import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/geo_utils.dart';

/// Bundled bitmaps: Windows does not need emoji flag support or a network.
class CountryBadge extends StatelessWidget {
  const CountryBadge({super.key, required this.code, this.size = 40});
  final String? code;
  final double size;
  @override
  Widget build(BuildContext context) {
    final known = code != null && GeoUtils.countryName(code, ru: false) != code!.toUpperCase();
    return SizedBox(width: size, height: size, child: Center(child: known
      ? ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.asset('assets/flags/${code!.toLowerCase()}.png', width: size, height: size * .75, fit: BoxFit.cover))
      : Icon(Icons.public_rounded, size: size * .6, color: context.palette.textSecondary)));
  }
}
