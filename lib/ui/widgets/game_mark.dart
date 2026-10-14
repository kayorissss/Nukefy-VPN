import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Bundled game and platform marks come from the reviewed sources in
/// assets/brands/games/NOTICE.txt. IDs are upstream filenames, so matching
/// stable words also covers new catalog rows.
class GameMark extends StatelessWidget {
  const GameMark({super.key, required this.id, this.size = 28});
  final String id;
  final double size;

  static const _marks = <String, String>{
    'battledotnet': 'battle',
    'battlenet': 'battle',
    'apexlegends': 'apexlegends',
    'rocketleague': 'epicgames',
    'armareforger': 'armareforger',
    'battlefield': 'battlefield',
    'bluearchive': 'bluearchive',
    'deadbydaylight': 'deadbydaylight',
    'minecraft': 'minecraft',
    'mortalkombat': 'mortalkombat',
    'warframe': 'warframe',
    'wutheringwaves': 'wutheringwaves',
    'cloudflare': 'cloudflare',
    'epic': 'epicgames',
    'electronicarts': 'ea',
    'fortnite': 'fortnite',
    'leagueoflegends': 'leagueoflegends',
    'origin': 'origin',
    'photon': 'photon',
    'riot': 'riotgames',
    'valorant': 'valorant',
    'roblox': 'roblox',
    'steam': 'steam',
    'ubisoft': 'ubisoft',
    'rainbowsix': 'ubisoft',
    'vrchat': 'vrchat',
  };

  String? _markFor(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized == 'ea' || normalized.startsWith('eagames')) return 'ea';
    for (final entry in _marks.entries) {
      final needle = entry.key.replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalized.contains(needle)) return entry.value;
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
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final p = context.palette;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: p.surface,
        border: Border.all(color: p.border),
      ),
      child: Icon(Icons.sports_esports_rounded, size: size * .58, color: p.textSecondary),
    );
  }
}
