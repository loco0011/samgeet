import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';

String _fmt(Duration d) => '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

/// Album art in a disc, ringed by ticks that light up as the song plays.
/// Drag around the ring to seek; swipe the cover to skip.
class DiscPlayer extends StatefulWidget {
  final PlayerController player;
  final Track track;
  final double size;
  final Color glow;
  const DiscPlayer({super.key, required this.player, required this.track, required this.size, required this.glow});

  /// True while the listener is dragging round the seek ring, so the
  /// swipe-down-to-minimize gesture on the player screen stays out of the way.
  static final ValueNotifier<bool> scrubbing = ValueNotifier(false);

  /// Height including the time labels underneath.
  static double heightFor(double size) => size + 36;

  @override
  State<DiscPlayer> createState() => _DiscPlayerState();
}

class _DiscPlayerState extends State<DiscPlayer> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 16));
  double? _drag; // 0..1 while the user drags the ring
  bool _dragging = false;
  bool _onRingDown = false;

  void _ringTouch(bool down) {
    _onRingDown = down;
    DiscPlayer.scrubbing.value = down;
  }

  @override
  void initState() {
    super.initState();
    _sync();
    widget.player.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    if (widget.player.isPlaying) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _pulse.stop();
      _spin.stop();
    }
  }

  @override
  void dispose() {
    if (_onRingDown) DiscPlayer.scrubbing.value = false;
    widget.player.removeListener(_sync);
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  double get _ringR => widget.size / 2 - 8;

  bool _onRing(Offset p) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final d = (p - c).distance;
    return d >= _ringR - 34 && d <= _ringR + 18;
  }

  double _fracAt(Offset p) {
    final c = Offset(widget.size / 2, widget.size / 2);
    final a = math.atan2(p.dy - c.dy, p.dx - c.dx) + math.pi / 2;
    var f = (a < 0 ? a + 2 * math.pi : a) / (2 * math.pi);
    // Don't let the value snap across the top of the ring.
    final prev = _drag;
    if (prev != null && (f - prev).abs() > 0.5) f = prev > 0.5 ? 1.0 : 0.0;
    return f.clamp(0.0, 1.0);
  }

  void _seekTo(double frac) {
    final dur = widget.player.player.duration ?? Duration.zero;
    if (dur == Duration.zero) return;
    widget.player.seek(Duration(milliseconds: (frac * dur.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final art = s * 0.68;
    final playing = widget.player.isPlaying;
    final pal = moodPalette(context).colors;

    return StreamBuilder<Duration>(
      stream: widget.player.player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = widget.player.player.duration ?? Duration.zero;
        final natural = dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        final frac = _drag ?? natural;
        final shown = _drag != null ? Duration(milliseconds: (_drag! * dur.inMilliseconds).round()) : pos;

        return Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: s,
            height: s,
            child: Listener(
              // Flag a touch on the ring right away, before the pan gesture starts.
              onPointerDown: (e) => _ringTouch(_onRing(e.localPosition)),
              onPointerUp: (_) => _ringTouch(false),
              onPointerCancel: (_) => _ringTouch(false),
              child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                if (_onRing(d.localPosition)) {
                  setState(() {
                    _dragging = true;
                    _drag = _fracAt(d.localPosition);
                  });
                }
              },
              onPanUpdate: (d) {
                if (_dragging) setState(() => _drag = _fracAt(d.localPosition));
              },
              onPanEnd: (_) {
                if (_dragging && _drag != null) _seekTo(_drag!);
                setState(() {
                  _dragging = false;
                  _drag = null;
                });
              },
              onTapUp: (d) {
                if (_onRing(d.localPosition)) _seekTo(_fracAt(d.localPosition));
              },
              child: Stack(alignment: Alignment.center, children: [
                // Breathing glow behind the cover.
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, _) => Container(
                    width: art,
                    height: art,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: widget.glow.withValues(alpha: 0.32 + 0.30 * _pulse.value), blurRadius: 46 + 26 * _pulse.value, spreadRadius: 4 + 8 * _pulse.value)],
                    ),
                  ),
                ),
                // Slowly turning light ring hugging the cover.
                RotationTransition(
                  turns: _spin,
                  child: Container(
                    width: art + 14,
                    height: art + 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: [pal[0], pal[1], pal[2], pal[0].withValues(alpha: 0), pal[0]]),
                    ),
                  ),
                ),
                Container(width: art + 8, height: art + 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg)),
                // The tick ring.
                CustomPaint(size: Size(s, s), painter: _TickRingPainter(frac: frac, ringRadius: _ringR, active: _dragging, colors: pal)),
                // Cover: swipe to skip.
                GestureDetector(
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -300) widget.player.next();
                    if (v > 300) widget.player.previous();
                  },
                  child: AnimatedScale(
                    scale: playing ? 1.0 : 0.94,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutBack,
                    child: Hero(
                      tag: 'player-art',
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: child)),
                        child: Artwork(widget.track.art(500), key: ValueKey(widget.track.id), size: art, circle: true, cacheSize: 700),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: s * 0.78,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt(shown), style: TextStyle(fontFamily: kDisplay, fontSize: 12.5, fontWeight: FontWeight.w700, color: _dragging ? moodPalette(context).light : Colors.white70)),
              Text(_fmt(dur), style: const TextStyle(fontFamily: kDisplay, fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white54)),
            ]),
          ),
        ]);
      },
    );
  }
}

class _TickRingPainter extends CustomPainter {
  final double frac;
  final double ringRadius;
  final bool active;
  final List<Color> colors;
  _TickRingPainter({required this.frac, required this.ringRadius, required this.active, required this.colors});

  static const _count = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final lit = Paint()..strokeCap = StrokeCap.round;
    final dim = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..color = Colors.white.withValues(alpha: 0.17);

    for (var i = 0; i < _count; i++) {
      final t = i / _count;
      final a = -math.pi / 2 + t * 2 * math.pi;
      final dir = Offset(math.cos(a), math.sin(a));
      final isLit = t <= frac;
      // Ticks near the playhead swell, like a scanner sweeping the ring.
      final near = (1 - ((t - frac).abs() * 14)).clamp(0.0, 1.0);
      final len = isLit ? 11.0 + 6 * near : 8.0;
      final outer = c + dir * ringRadius;
      final inner = c + dir * (ringRadius - len);
      if (isLit) {
        lit
          ..strokeWidth = 2.6 + near * 1.2
          ..color = AppColors.along(colors, t);
        canvas.drawLine(inner, outer, lit);
      } else {
        canvas.drawLine(inner, outer, dim);
      }
    }

    // Glowing playhead.
    final a = -math.pi / 2 + frac * 2 * math.pi;
    final p = c + Offset(math.cos(a), math.sin(a)) * (ringRadius + 2);
    final col = AppColors.along(colors, frac);
    canvas.drawCircle(p, active ? 15 : 11, Paint()..color = col.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.drawCircle(p, active ? 7.5 : 5.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TickRingPainter old) => old.frac != frac || old.active != active || old.ringRadius != ringRadius || old.colors != colors;
}
