import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'nukefy_logo.dart';

/// Short branded intro: logo and name for about a second, then a smooth
/// fade into the real interface. The overlay is removed from the tree once
/// finished, so it never intercepts input or keeps a ticker alive.
class NukefySplash extends StatefulWidget {
  const NukefySplash({super.key, required this.child});

  final Widget child;

  @override
  State<NukefySplash> createState() => _NukefySplashState();
}

class _NukefySplashState extends State<NukefySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().then((_) {
      if (mounted) setState(() => _finished = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_finished)
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0).animate(
              CurvedAnimation(parent: _controller, curve: const Interval(0.72, 1, curve: Curves.easeIn)),
            ),
            child: ColoredBox(
              color: p.background,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: Tween<double>(begin: 0.86, end: 1).animate(
                        CurvedAnimation(parent: _controller, curve: const Interval(0, 0.55, curve: Curves.easeOutBack)),
                      ),
                      child: FadeTransition(
                        opacity: CurvedAnimation(parent: _controller, curve: const Interval(0, 0.35)),
                        child: const NukefyLogo(size: 108, glow: false),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeTransition(
                      opacity: CurvedAnimation(parent: _controller, curve: const Interval(0.25, 0.7)),
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
                          CurvedAnimation(parent: _controller, curve: const Interval(0.25, 0.7, curve: Curves.easeOutCubic)),
                        ),
                        child: Text(
                          'NUKEFY VPN',
                          style: AppTextStyles.status.copyWith(
                            color: p.text,
                            fontSize: 15,
                            letterSpacing: 4,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
