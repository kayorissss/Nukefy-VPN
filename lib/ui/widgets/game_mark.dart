import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Bundled platform marks; new/unknown games use a distinct text monogram.
/// The remote catalog never supplies executable assets or arbitrary image URLs.
class GameMark extends StatelessWidget {
  const GameMark({super.key, required this.id, this.size = 28});
  final String id;
  final double size;

  static const _marks = {
    'Steam': 'steam',
    'EpicGames_Fortnite': 'epicgames',
    'RiotGames_Valorant': 'riotgames',
    'LeagueOfLegends': 'riotgames',
    'BattleNet': 'battledotnet',
    'Ubisoft_Rainbow_Six_Siege': 'ubisoft',
    'Roblox': 'roblox',
    'EA_Origin': 'ea',
    'Battlefield6': 'ea',
  };

  @override
  Widget build(BuildContext context) {
    final mark = _marks[id];
    if (mark != null) return Image.asset('assets/brands/games/$mark.png', width: size, height: size, color: context.palette.accent);
    final letters = id.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return SizedBox(width: size, height: size, child: Center(child: Text(
      letters.length > 1 ? letters.substring(0, 2).toUpperCase() : letters.toUpperCase(),
      style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w800, color: context.palette.accent),
    )));
  }
}
