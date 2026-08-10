import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Palette for the onboarding backdrop, one entry per step.
///
/// The gradient shifts as the member advances, so progress is felt before it is
/// read. Painted, not bundled: no image asset, no download, no decode cost.
class AuroraPalette {
  const AuroraPalette({
    required this.top,
    required this.bottom,
    required this.glowPrimary,
    required this.glowSecondary,
  });

  final Color top;
  final Color bottom;
  final Color glowPrimary;
  final Color glowSecondary;

  static const location = AuroraPalette(
    top: Color(0xFF12102A),
    bottom: Color(0xFF2A1B5E),
    glowPrimary: Color(0xFF6C5CE7),
    glowSecondary: Color(0xFF2FB4D9),
  );

  static const arrival = AuroraPalette(
    top: Color(0xFF14122E),
    bottom: Color(0xFF3B1E63),
    glowPrimary: Color(0xFF9B6CF1),
    glowSecondary: Color(0xFFE8A33A),
  );

  static const personas = AuroraPalette(
    top: Color(0xFF101A2E),
    bottom: Color(0xFF1F3F5E),
    glowPrimary: Color(0xFF19C29A),
    glowSecondary: Color(0xFF6C5CE7),
  );

  static AuroraPalette lerp(AuroraPalette a, AuroraPalette b, double t) =>
      AuroraPalette(
        top: Color.lerp(a.top, b.top, t)!,
        bottom: Color.lerp(a.bottom, b.bottom, t)!,
        glowPrimary: Color.lerp(a.glowPrimary, b.glowPrimary, t)!,
        glowSecondary: Color.lerp(a.glowSecondary, b.glowSecondary, t)!,
      );
}

class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.palette, required this.child});

  final AuroraPalette palette;
  final Widget child;

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with TickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  late final AnimationController _blend = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: 1,
  );

  late AuroraPalette _from = widget.palette;
  late AuroraPalette _to = widget.palette;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduce-motion members get a still gradient. It also keeps the ambient
    // drift from running forever, which no widget test could ever settle.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      // Start from whatever is on screen right now, so a fast tap through two
      // steps does not snap back to the palette of the step before last.
      _from = AuroraPalette.lerp(_from, _to, _blend.value);
      _to = widget.palette;
      _blend.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _blend.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([_drift, _blend]),
    builder: (context, child) {
      final palette = AuroraPalette.lerp(
        _from,
        _to,
        Curves.easeOutCubic.transform(_blend.value),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [palette.top, palette.bottom],
          ),
        ),
        child: CustomPaint(
          painter: _AuroraGlowPainter(palette: palette, phase: _drift.value),
          child: child,
        ),
      );
    },
    child: widget.child,
  );
}

class _AuroraGlowPainter extends CustomPainter {
  const _AuroraGlowPainter({required this.palette, required this.phase});

  final AuroraPalette palette;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = phase * 2 * math.pi;
    _blob(
      canvas,
      Offset(size.width * (0.18 + 0.06 * math.sin(angle)),
          size.height * (0.16 + 0.04 * math.cos(angle))),
      size.width * 0.68,
      palette.glowPrimary,
      0.34,
    );
    _blob(
      canvas,
      Offset(size.width * (0.88 + 0.05 * math.cos(angle * 0.8)),
          size.height * (0.34 + 0.05 * math.sin(angle * 0.8))),
      size.width * 0.52,
      palette.glowSecondary,
      0.22,
    );
    _blob(
      canvas,
      Offset(size.width * 0.5, size.height * (1.02 + 0.03 * math.sin(angle * 1.3))),
      size.width * 0.9,
      palette.glowPrimary,
      0.18,
    );
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color, double alpha) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraGlowPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.palette != palette;
}
