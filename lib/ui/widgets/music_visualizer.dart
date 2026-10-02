import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small, deliberately quiet playback indicator. It only moves while the
/// player is active and is laid out as a normal widget, so it cannot cover a
/// button, title, or error message.
class MusicVisualizer extends StatefulWidget {
  const MusicVisualizer({
    super.key,
    required this.active,
    required this.color,
    this.height = 22,
    this.barCount = 12,
  });

  final bool active;
  final Color color;
  final double height;
  final int barCount;

  @override
  State<MusicVisualizer> createState() => _MusicVisualizerState();
}

class _MusicVisualizerState extends State<MusicVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant MusicVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = math.max<int>(4, widget.barCount);
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: count * 4.5,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < count; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: _Bar(
                      height: _barHeight(index, count),
                      color: widget.color.withValues(alpha: widget.active ? .78 : .28),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _barHeight(int index, int count) {
    if (!widget.active) return math.max(3, widget.height * (.16 + (index.isEven ? .05 : .02)));
    final phase = _controller.value * math.pi * 2;
    final wave = math.sin(phase * 1.15 + index * .74).abs();
    final accent = math.sin(phase * .61 + index * 1.7).abs();
    final edge = 1 - ((index - (count - 1) / 2).abs() / count) * .22;
    return math.max(3, widget.height * (.22 + (wave * .58 + accent * .2) * edge));
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Plain container: the parent already rebuilds every animation frame, an
    // AnimatedContainer per bar added a second ticker for each of them.
    return Container(
      width: 2.4,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
