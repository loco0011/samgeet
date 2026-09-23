import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../player/player_controller.dart';
import '../screens/now_playing_screen.dart';
import '../theme.dart';
import 'common.dart';
import 'dominant_color.dart';
import 'glass.dart';
import '../mood_theme.dart';

/// The floating "now playing" capsule: a glowing progress ring around a
/// spinning cover. Swipe sideways to skip, tap to expand.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, anim) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: track == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Padding(
              key: const ValueKey('mini'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: DominantColorBuilder(
                url: track.art(150),
                builder: (context, color) => GestureDetector(
                  onTap: () => openNowPlaying(context),
                  onHorizontalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -300) player.next();
                    if (v > 300) player.previous();
                  },
                  onVerticalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) < -300) openNowPlaying(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34),
                      boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 8))],
                    ),
                    child: GlassBox(
                      radius: 34,
                      blur: true,
                      tint: color,
                      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                      child: Row(children: [
                        _RingCover(player: player),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Align(
                              key: ValueKey(track.id),
                              alignment: Alignment.centerLeft,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 13.5)),
                                  const SizedBox(height: 2),
                                  Text(track.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Consumer<LibraryStore>(
                          builder: (_, lib, _) => IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => lib.toggleFavorite(track),
                            icon: Icon(
                              lib.isFavorite(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 22,
                              color: lib.isFavorite(track.id) ? AppColors.pink : Colors.white70,
                            ),
                          ),
                        ),
                        _PlayPause(player: player),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Circular cover that spins while playing, wrapped in a glowing progress arc.
class _RingCover extends StatefulWidget {
  final PlayerController player;
  const _RingCover({required this.player});

  @override
  State<_RingCover> createState() => _RingCoverState();
}

class _RingCoverState extends State<_RingCover> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void initState() {
    super.initState();
    _sync();
    widget.player.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    if (widget.player.isPlaying) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_sync);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.player.current;
    const size = 50.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        StreamBuilder<Duration>(
          stream: widget.player.player.positionStream,
          builder: (_, snap) {
            final dur = widget.player.player.duration ?? Duration.zero;
            final frac = dur.inMilliseconds == 0 ? 0.0 : ((snap.data ?? Duration.zero).inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
            return CustomPaint(size: const Size(size, size), painter: _ArcPainter(frac, moodPalette(context).colors));
          },
        ),
        RotationTransition(turns: _spin, child: Artwork(track?.image ?? '', size: size - 10, circle: true, cacheSize: 150)),
      ]),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double frac;
  final List<Color> colors;
  _ArcPainter(this.frac, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(2);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..color = Colors.white.withValues(alpha: 0.14));
    if (frac <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: 3 * math.pi / 2, colors: [...colors, colors.first]).createShader(rect);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * frac, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.frac != frac || old.colors != colors;
}

class _PlayPause extends StatelessWidget {
  final PlayerController player;
  const _PlayPause({required this.player});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return StreamBuilder<PlayerState>(
      stream: player.player.playerStateStream,
      builder: (_, snap) {
        final state = snap.data;
        final loading = state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering;
        final playing = state?.playing ?? false;
        return Pressable(
          onTap: player.togglePlay,
          scale: 0.9,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: mood.gradient, boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.55), blurRadius: 14)]),
            child: Stack(alignment: Alignment.center, children: [
              if (loading && playing) const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), size: 28),
              ),
            ]),
          ),
        );
      },
    );
  }
}

void openNowPlaying(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    // Not opaque: swiping the player down reveals the app underneath.
    opaque: false,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  ));
}
