import 'package:flutter/material.dart';

/// Independent sections become columns, rather than a stretched phone page.
///
/// [fullWidthCount] reserves the first items for a page header/banner. This
/// matters on desktop: a tab strip or an update notice should not become the
/// first card in one column while the other column starts with settings.
class ResponsiveSections extends StatelessWidget {
  const ResponsiveSections({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(20),
    this.minColumnWidth = 460,
    this.maxColumns = 3,
    this.fullWidthCount = 0,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double minColumnWidth;
  final int maxColumns;
  final int fullWidthCount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
        final sections = children.where((w) => w is! SizedBox).toList();
        final headerCount = fullWidthCount.clamp(0, sections.length).toInt();
        final header = sections.take(headerCount);
        final content = sections.skip(headerCount).toList();
        // A page with one remaining section must use the whole available
        // width. The old column calculation put Appearance and About into
        // the first half of the desktop canvas and left a large dead area on
        // the right, which looked like a broken fullscreen layout.
        final requestedColumns = ((bounds.maxWidth - 40) / minColumnWidth).floor().clamp(1, maxColumns).toInt();
        final columns = content.isEmpty ? 1 : requestedColumns.clamp(1, content.length).toInt();

        // One gap value for every mode: the same page used to space cards by
        // 14 px in one column and 16 px in two, so the rhythm changed with the
        // window size.
        const gap = 14.0;
        const columnGap = 20.0;

        Widget columnsView() {
          if (columns == 1) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in content)
                  Padding(padding: EdgeInsets.only(bottom: gap), child: child),
              ],
            );
          }
          // Explicit rows instead of independent column stacks: cards that sit
          // side by side now share a row height, so their tops and bottoms line
          // up instead of one column ending higher than the other.
          final rows = <List<Widget>>[];
          for (var i = 0; i < content.length; i += columns) {
            final row = content.sublist(i, (i + columns).clamp(0, content.length).toInt());
            rows.add(row);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows)
                Padding(
                  padding: EdgeInsets.only(bottom: gap),
                  child: row.length == 1
                      ? row.first
                      : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var col = 0; col < columns; col++) ...[
                                if (col > 0) const SizedBox(width: columnGap),
                                Expanded(
                                  child: col < row.length
                                      ? row[col]
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
            ],
          );
        }

        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in header)
                Padding(padding: const EdgeInsets.only(bottom: 14), child: child),
              columnsView(),
            ],
          ),
        );
      });
}

class ResponsiveTiles extends StatelessWidget {
  const ResponsiveTiles({super.key, required this.children, this.minWidth = 350});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final columns = (bounds.maxWidth / minWidth).floor().clamp(1, 4).toInt();
    final width = bounds.maxWidth / columns;
    return Wrap(children: [for (final child in children) SizedBox(width: width, child: child)]);
  });
}

class ResponsiveFrame extends StatelessWidget {
  const ResponsiveFrame({super.key, required this.child, this.maxWidth = 1400});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
}
