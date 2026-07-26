import 'dart:ui';
import 'package:flutter/material.dart';

import '../theme/background_controller.dart';

/// Frosted, translucent container used across the app for the
/// "liquid glass" design language.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
    this.blur = 18,
    this.opacity,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double blur;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = isDark ? Colors.white : Colors.white;
    final surfaceOpacity = opacity ?? (isDark ? 0.08 : 0.45);
    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withOpacity(surfaceOpacity + 0.08),
                  tint.withOpacity(surfaceOpacity),
                ],
              ),
              border: Border.all(
                color: tint.withOpacity(isDark ? 0.15 : 0.6),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Backdrop that all glass surfaces blur against: the user's app-level
/// wallpaper image when one is chosen (with a translucent gradient wash on
/// top so the glass keeps its liquid look), otherwise an animated gradient.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark
        ? const [Color(0xFF1B1730), Color(0xFF12101C), Color(0xFF251A3A)]
        : const [Color(0xFFE8E4FA), Color(0xFFF2F1FA), Color(0xFFDCE9F7)];
    BackgroundController.instance.load();
    return ListenableBuilder(
      listenable: BackgroundController.instance,
      builder: (context, _) {
        final wallpaper = BackgroundController.instance.appWallpaper;
        if (wallpaper.asset != null && wallpaper.asset!.isNotEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(wallpaper.asset!),
                fit: BoxFit.cover,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colors.first.withOpacity(0.25),
                    colors.last.withOpacity(0.25),
                  ],
                ),
              ),
              child: child,
            ),
          );
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// Page route with a fast fade+slide transition, used for a fluid feel.
class GlassPageRoute<T> extends PageRouteBuilder<T> {
  GlassPageRoute({required Widget page})
      : super(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Lightweight shimmer used as a loading state, no external packages.
class GlassShimmer extends StatefulWidget {
  const GlassShimmer({super.key, this.height = 64, this.count = 3});

  final double height;
  final int count;

  @override
  State<GlassShimmer> createState() => _GlassShimmerState();
}

class _GlassShimmerState extends State<GlassShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Column(
          children: List.generate(widget.count, (i) {
            final t = (_controller.value + i * 0.2) % 1.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: base.withOpacity(0.35 + 0.25 * (1 - (t - 0.5).abs() * 2)),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
