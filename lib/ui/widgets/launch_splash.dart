import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

/// The logo coming alive when the app opens.
///
/// Android shows its own, still splash (the same picture, `splash_logo.png`,
/// on the same colour) until Flutter draws its first frame. This overlay starts
/// as an exact copy of that, so the hand-over can't be seen, then the logo
/// beats, a shine runs over the chrome, rings ripple out and a few bars dance underneath.
/// Finally the logo zooms through the screen into the app. A tap skips it.
class LaunchSplash extends StatefulWidget {
  final Widget child;

  /// Android version (API level); decides how big Android drew the logo.
  final int androidSdk;
  const LaunchSplash({super.key, required this.child, this.androidSdk = 31});

  /// The colour behind Android's launch logo (`launcher_bg`).
  static const background = Color(0xFF04061C);

  @override
  State<LaunchSplash> createState() => _LaunchSplashState();
}

class _LaunchSplashState extends State<LaunchSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _done = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _startWhenSmooth());
  }

  /// Starts once frames come steadily. Right after launch the phone is still
  /// setting the app up and can freeze for a second or more; an animation
  /// started then would be over before any of it was drawn. Until then the
  /// logo just sits still, looking exactly like Android's own splash.
  Future<void> _startWhenSmooth() async {
    final binding = SchedulerBinding.instance;
    final giveUp = DateTime.now().add(const Duration(milliseconds: 2500));
    var last = DateTime.now();
    var steady = 0;
    while (mounted && steady < 3 && DateTime.now().isBefore(giveUp)) {
      binding.scheduleFrame();
      await binding.endOfFrame;
      final now = DateTime.now();
      steady = now.difference(last) < const Duration(milliseconds: 50) ? steady + 1 : 0;
      last = now;
    }
    if (!mounted || _c.isAnimating || _c.value > 0) return; // skipped by a tap meanwhile
    // Nothing to watch when the phone asks for less motion: a quick fade instead.
    if (MediaQuery.of(context).disableAnimations) _c.value = 0.78;
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _skip() {
    if (_c.value < 0.78) _c.forward(from: 0.78);
  }

  /// Size Android drew the logo at: from Android 12 the splash icon (no icon
  /// background) is 288dp; before that the 432px bitmap is drawn pixel for pixel.
  double _logoSize(BuildContext context) =>
      widget.androidSdk >= 31 ? 288 : 432 / MediaQuery.devicePixelRatioOf(context);

  @override
  Widget build(BuildContext context) {
    // The child stays first in the same Stack, so the app below is never rebuilt from scratch.
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (!_done)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: AnimatedBuilder(animation: _c, builder: (context, _) => _frame(context, _c.value)),
        ),
    ]);
  }

  static double _span(double t, double a, double b, [Curve curve = Curves.linear]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  Widget _frame(BuildContext context, double t) {
    final size = _logoSize(context);
    // Beat: swell, then settle with a little bounce.
    final beat = t < 0.28 ? 1 + 0.14 * _span(t, 0.12, 0.28, Curves.easeOutCubic) : 1.14 - 0.14 * _span(t, 0.28, 0.5, Curves.elasticOut);
    final exit = _span(t, 0.78, 1, Curves.easeInCubic);
    final scale = beat * (1 + 6 * exit);
    final glow = _span(t, 0.1, 0.35) * (1 - _span(t, 0.7, 0.85));
    final shine = _span(t, 0.3, 0.62, Curves.easeInOut);
    final bars = _span(t, 0.42, 0.68, Curves.easeOutCubic) * (1 - _span(t, 0.74, 0.84));

    return Opacity(
      opacity: 1 - _span(t, 0.84, 1, Curves.easeIn),
      child: ColoredBox(
        color: LaunchSplash.background,
        child: Stack(alignment: Alignment.center, children: [
          // Warm glow behind the logo.
          Opacity(
            opacity: glow,
            child: Container(
              width: size * 1.6,
              height: size * 1.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppColors.ember2.withValues(alpha: 0.55), AppColors.ember1.withValues(alpha: 0.18), Colors.transparent]),
              ),
            ),
          ),
          // Rings rippling out, like sound.
          CustomPaint(size: Size.square(size * 2.6), painter: _RipplePainter(t: t, base: size * 0.22)),
          Transform.scale(
            scale: scale,
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0)],
                stops: [shine - 0.15, shine, shine + 0.15].map((s) => s.clamp(0.0, 1.0)).toList(),
              ).createShader(r),
              child: Image.asset('assets/splash_logo.png', width: size, height: size, gaplessPlayback: true),
            ),
          ),
          // A few bouncing bars, under the logo.
          Positioned.fill(
            top: size * 0.8,
            child: Center(
              child: Opacity(
                opacity: bars,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - bars)),
                  child: SizedBox(height: 22, child: _Bars(t: t)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double t;
  final double base;
  _RipplePainter({required this.t, required this.base});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = ((t - 0.16 - i * 0.1) / 0.5).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final eased = Curves.easeOutCubic.transform(p);
      final r = base + (size.width / 2 - base) * eased;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - p) + 0.5
          ..color = AppColors.ringAt(i / 2).withValues(alpha: 0.75 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t;
}

/// Five little equalizer bars dancing to no music at all.
class _Bars extends StatelessWidget {
  final double t;
  const _Bars({required this.t});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < 5; i++)
        Container(
          width: 4,
          height: 6 + 16 * (0.5 + 0.5 * math.sin(t * 28 + i * 1.3)).abs(),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: AppColors.ringAt(i / 4)),
        ),
    ]);
  }
}
