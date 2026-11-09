import 'dart:ui';
import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// A bounded desktop glass surface. Data panes stay opaque enough to read;
/// only explicitly opted-in chrome samples and blurs its backdrop.
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.all(16),
    this.enableBlur = false,
  });
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  final bool enableBlur;
  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  bool _hovered = false;
  Offset _light = const Offset(-.65, -.85);
  static final _filter = ImageFilter.blur(sigmaX: 16, sigmaY: 16);

  @override
  Widget build(BuildContext context) {
    final colors = LiquidGlassColors.of(context);
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        colors.highContrast;
    final duration = reduced
        ? Duration.zero
        : const Duration(milliseconds: 160);
    final radius = BorderRadius.circular(V2DesignTokens.radiusXl);
    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        onEnter: (_) {
          if (!reduced) setState(() => _hovered = true);
        },
        onExit: (_) => setState(() {
          _hovered = false;
          _light = const Offset(-.65, -.85);
        }),
        onHover: reduced
            ? null
            : (event) {
                final size = context.size;
                if (size == null || size.isEmpty) return;
                // Quantized position avoids repainting the entire pane on every pixel.
                final point = Offset(
                  ((event.localPosition.dx / size.width * 2 - 1) * 6).round() /
                      6,
                  ((event.localPosition.dy / size.height * 2 - 1) * 6).round() /
                      6,
                );
                if (point != _light) setState(() => _light = point);
              },
        child: AnimatedContainer(
          duration: duration,
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: colors.dark ? .22 : .055),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: colors.primary.withValues(alpha: _hovered ? .09 : .025),
                blurRadius: 16,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: _backdrop(
              colors,
              TweenAnimationBuilder<Offset>(
                duration: duration,
                tween: Tween(end: reduced ? const Offset(-.65, -.85) : _light),
                builder: (context, light, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: colors.surfaceGradient(chrome: widget.enableBlur),
                  ),
                  child: Stack(
                    children: [
                      child!,
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _GlassEdgePainter(
                              light: light,
                              colors: colors,
                              hovered: _hovered && !reduced,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backdrop(LiquidGlassColors colors, Widget child) =>
      widget.enableBlur && !colors.highContrast
      ? BackdropFilter(filter: _filter, child: child)
      : child;
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({
    required this.light,
    required this.colors,
    required this.hovered,
  });
  final Offset light;
  final LiquidGlassColors colors;
  final bool hovered;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.75);
    if (rect.isEmpty) return;
    final shape = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(V2DesignTokens.radiusXl),
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    if (colors.highContrast) {
      canvas.drawRRect(shape, edge..color = colors.stroke);
      return;
    }
    edge.shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: colors.dark ? .50 : .98),
        colors.stroke,
        colors.primary.withValues(alpha: .12),
        Colors.white.withValues(alpha: colors.dark ? .18 : .80),
      ],
      stops: const [0, .38, .7, 1],
    ).createShader(rect);
    canvas.drawRRect(shape, edge);
    final reflection = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hovered ? 2.4 : 1.6
      ..shader = RadialGradient(
        center: Alignment(light.dx, light.dy),
        radius: 1.1,
        colors: [
          Colors.white.withValues(alpha: hovered ? .95 : .60),
          colors.primary.withValues(alpha: .15),
          Colors.transparent,
        ],
        stops: const [0, .45, 1],
      ).createShader(rect);
    canvas.drawRRect(shape.deflate(1.8), reflection);
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) =>
      old.light != light ||
      old.hovered != hovered ||
      old.colors.dark != colors.dark ||
      old.colors.highContrast != colors.highContrast;
}
