import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import 'nukefy_logo.dart';

/// Short branded intro: the РКН-тянka artwork on the right, the client's own
/// branding on the left, then a smooth fade into the real interface. The
/// overlay leaves the tree once finished, so it never intercepts input.
class NukefySplash extends StatefulWidget {
  const NukefySplash({super.key, required this.child, this.message});

  final Widget child;

  /// Optional line under the name (used by the uninstall flow).
  final String? message;

  @override
  State<NukefySplash> createState() => _NukefySplashState();
}

class _NukefySplashState extends State<NukefySplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
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
              CurvedAnimation(parent: _controller, curve: const Interval(0.76, 1, curve: Curves.easeIn)),
            ),
            child: ColoredBox(
              color: p.background,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 720;
                  final brand = _Brand(strings: widget.message, controller: _controller);
                  final art = _Art(controller: _controller);
                  return Row(
                    children: [
                      // Left half: our name, logo and the progress dot line.
                      Expanded(
                        flex: narrow ? 1 : 6,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: brand,
                          ),
                        ),
                      ),
                      // Right half: the artwork the user attached.
                      if (!narrow)
                        Expanded(
                          flex: 5,
                          child: Align(alignment: Alignment.bottomRight, child: art),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.controller, this.strings});

  final AnimationController controller;
  final String? strings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget wrap(Widget child, double begin, double end) => FadeTransition(
          opacity: CurvedAnimation(parent: controller, curve: Interval(begin, end)),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(-0.06, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: controller, curve: Interval(begin, end, curve: Curves.easeOutCubic))),
            child: child,
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        wrap(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NukefyLogo(size: 64, glow: true),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Nukefy Client',
                      style: AppTextStyles.headline.copyWith(fontSize: 22, letterSpacing: 1.2, color: p.text)),
                  const SizedBox(height: 4),
                  Text('sing-box · Android и Windows',
                      style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          0.0,
          0.45,
        ),
        const SizedBox(height: 22),
        wrap(
          Text(
            strings ?? 'Загрузка…',
            style: AppTextStyles.bodySecondary.copyWith(color: p.textSecondary, fontSize: 12.5),
          ),
          0.3,
          0.7,
        ),
        const SizedBox(height: 12),
        // Three soft dots instead of the old progress bar: the bar read as
        // yellow stripes under the caption with a warm accent colour.
        wrap(
          SizedBox(
            height: 10,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Opacity(
                      opacity: (0.25 + 0.75 * ((controller.value * 3 - i).clamp(0.0, 1.0) * (1 - ((controller.value * 3 - i - 1).clamp(0.0, 1.0))))).clamp(0.2, 1.0),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: p.textSecondary, shape: BoxShape.circle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          0.15,
          0.6,
        ),
      ],
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FadeTransition(
      opacity: CurvedAnimation(parent: controller, curve: const Interval(0.12, 0.85)),
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0.06, 0.04), end: Offset.zero)
            .animate(CurvedAnimation(parent: controller, curve: const Interval(0.12, 0.85, curve: Curves.easeOutCubic))),
        child: ShaderMask(
          // Fade the artwork into the background instead of cutting it with a
          // hard rectangle: no visible seam on any window size.
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [p.background.withValues(alpha: 0), p.background],
            stops: const [0.0, 0.35],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: Image.asset(
            'assets/rkntyan.png',
            fit: BoxFit.contain,
            alignment: Alignment.bottomRight,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
