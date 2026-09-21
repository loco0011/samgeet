import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mood_theme.dart';
import '../theme.dart';

/// The app's living backdrop: three soft light blobs drifting slowly over a
/// faint dot grid. While music plays, the light picks up the album's colour.
class AuroraBackground extends StatefulWidget {
  final Widget child;

  /// Colour of the current album art (null when nothing is playing).
  final Color? tint;

  /// Colours of the current mood; the backdrop drifts between palettes.
  final MoodPalette palette;
  const AuroraBackground({super.key, required this.child, this.tint, this.palette = MoodPalette.brand});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 48))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: AppColors.bg),
      // Static grid is painted once and cached.
      const RepaintBoundary(child: CustomPaint(painter: _DotGridPainter())),
      RepaintBoundary(
        // Colour and strength animate separately: the colour must always be
        // non-null, and "no music" simply fades the strength back to zero.
        child: TweenAnimationBuilder<MoodPalette>(
          tween: MoodPaletteTween(end: widget.palette),
          duration: const Duration(milliseconds: 1600),
          builder: (context, palette, _) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: widget.tint ?? widget.palette.accent),
            duration: const Duration(milliseconds: 1200),
            builder: (context, tint, _) => TweenAnimationBuilder<double>(
              // Mood leads; the album art only adds a hint of its own colour.
              tween: Tween(end: widget.tint == null ? 0.0 : 0.28),
              duration: const Duration(milliseconds: 1200),
              builder: (context, strength, _) => AnimatedBuilder(
                animation: _c,
                builder: (_, _) => CustomPaint(painter: _AuroraPainter(_c.value, tint ?? palette.accent, strength, palette.colors)),
              ),
            ),
          ),
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final Color tint;
  final double strength;
  final List<Color> colors;
  _AuroraPainter(this.t, this.tint, this.strength, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = math.max(w, h) * 0.62;
    // With music playing, blend the palette towards the album colour.
    Color mix(Color c) => Color.lerp(c, tint, strength)!;

    void blob(Offset centre, Color colour, double alpha) {
      final rect = Rect.fromCircle(center: centre, radius: r);
      canvas.drawCircle(
        centre,
        r,
        Paint()..shader = RadialGradient(colors: [colour.withValues(alpha: alpha), colour.withValues(alpha: 0)]).createShader(rect),
      );
    }

    final a = t * 2 * math.pi;
    blob(Offset(w * (0.12 + 0.22 * math.sin(a)), h * (0.08 + 0.07 * math.cos(a * 1.3))), mix(colors[1]), 0.30);
    blob(Offset(w * (0.92 + 0.10 * math.cos(a * 0.8)), h * (0.38 + 0.12 * math.sin(a))), mix(colors[0]), 0.16);
    blob(Offset(w * (0.28 + 0.20 * math.sin(a * 1.2 + 2)), h * (0.98 + 0.05 * math.cos(a))), mix(colors[2]), 0.22);
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t || old.tint != tint || old.strength != strength || old.colors != colors;
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const gap = 26.0;
    for (var y = gap / 2; y < size.height; y += gap) {
      for (var x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => false;
}
