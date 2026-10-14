import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/ui/widgets/responsive_sections.dart';
import 'package:nukefy_vpn/ui/widgets/section_card.dart';

/// Regression guard for the settings grid: at desktop widths the section
/// cards used to be forced into an IntrinsicHeight row, which under-measured
/// cards and painted the next row over them. Cards must keep their own
/// height, never overlap, and never report a layout overflow at the widths
/// people actually run the app at.
void main() {
  Widget card(String title, double height) => SectionCard(
        key: ValueKey(title),
        title: title,
        icon: Icons.tune_rounded,
        child: Column(
          children: [
            SizedBox(height: height),
            // A LayoutBuilder child is what broke intrinsic measuring.
            LayoutBuilder(builder: (context, _) => const Text('row')),
            const Text('last line'),
          ],
        ),
      );

  for (final width in [1280.0, 1500.0, 1920.0]) {
    testWidgets('settings grid does not overlap at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveSections(
              minColumnWidth: 460,
              maxColumns: 2,
              children: [
                card('general', 180),
                card('vpn', 320),
                card('subs', 140),
                card('about', 260),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'layout overflow at $width');

      final rects = ['general', 'vpn', 'subs', 'about']
          .map((title) => tester.getRect(find.byKey(ValueKey(title))))
          .toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: 'cards $i and $j overlap at $width: ${rects[i]} vs ${rects[j]}',
          );
        }
      }
      // The tall card must keep its full height instead of being squashed
      // into the row: its bottom is below the short neighbour's bottom.
      expect(rects[1].bottom, greaterThan(rects[0].bottom + 100));
    });
  }

  testWidgets('settings tile keeps its title readable in a narrow card', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionCard(
            title: 'appearance',
            child: SettingsTile(
              icon: Icons.language_rounded,
              title: 'Язык интерфейса приложения',
              trailing: SizedBox(width: 190, height: 36),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Язык интерфейса приложения'), findsOneWidget);
  });
}
