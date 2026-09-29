import 'package:flutter/material.dart';

/// Independent sections become columns, rather than a stretched phone page.
class ResponsiveSections extends StatelessWidget {
  const ResponsiveSections({super.key, required this.children, this.padding = const EdgeInsets.all(20), this.minColumnWidth = 460});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double minColumnWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) {
    final columns = ((bounds.maxWidth - 40) / minColumnWidth).floor().clamp(1, 3).toInt();
    final sections = children.where((w) => w is! SizedBox).toList();
    return SingleChildScrollView(padding: padding, child: columns == 1
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final child in sections) Padding(padding: const EdgeInsets.only(bottom: 14), child: child)])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var col = 0; col < columns; col++) ...[
          if (col > 0) const SizedBox(width: 20),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = col; i < sections.length; i += columns) Padding(padding: const EdgeInsets.only(bottom: 16), child: sections[i])])),
        ]]));
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
