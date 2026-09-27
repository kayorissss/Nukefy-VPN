import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Platform marks for the catalogue. IDs are upstream filenames, so matching
/// by stable keywords keeps new game entries from losing their platform icon.
class GameMark extends StatelessWidget {
  const GameMark({super.key, required this.id, this.size = 28});
  final String id;
  final double size;

  static const _marks = {
    'steam': 'steam',
    'epic': 'epicgames',
    'riot': 'riotgames',
    'valorant': 'riotgames',
    'leagueoflegends': 'riotgames',
    'league_of_legends': 'riotgames',
    'battlenet': 'battledotnet',
    'battle.net': 'battledotnet',
    'ubisoft': 'ubisoft',
    'rainbowsix': 'ubisoft',
    'rainbow_six': 'ubisoft',
    'roblox': 'roblox',
    'ea_': 'ea',
    'origin': 'ea',
    'battlefield': 'ea',
  };

  String? _markFor(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '');
    for (final entry in _marks.entries) {
      if (normalized.contains(entry.key.replaceAll(RegExp(r'[^a-z0-9._]'), ''))) return entry.value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final mark = _markFor(id);
    if (mark != null) {
      return Image.asset(
        'assets/brands/games/$mark.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        color: context.palette.accent,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final letters = id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.sports_esports_rounded,
        size: size * .72,
        color: context.palette.accent,
        semanticLabel: letters.isEmpty ? null : letters,
      ),
    );
  }
}
