import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/share_service.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../mood_theme.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/disc_player.dart';
import '../widgets/dominant_color.dart';
import '../widgets/player_sheets.dart';
import '../widgets/track_widgets.dart';

class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final track = player.current;
    if (track == null) {
      // Queue emptied while open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const Scaffold();
    }

    return DominantColorBuilder(
      url: track.art(150),
      builder: (context, color) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: const Duration(milliseconds: 800),
        builder: (context, animated, _) {
          // The song's mood leads the colour; the album art tints it.
          final moodC = context.watch<MoodController>();
          final base = animated ?? color;
          final accent = !moodC.themed ? base : Color.lerp(base, moodC.palette.colors[1], 0.55)!;
          return _SwipeDownToMinimize(
              child: Scaffold(
                // Solid, so nothing from the page underneath shows through the player.
                backgroundColor: AppColors.bg,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accent.withValues(alpha: 0.62), Color.lerp(accent, AppColors.bg, 0.86)!, AppColors.bg],
                  stops: const [0, 0.45, 0.9],
                ),
              ),
              child: SafeArea(
                child: LayoutBuilder(builder: (context, box) {
                  final landscape = box.maxWidth > box.maxHeight;

                  if (landscape) {
                    // Two panes: artwork on the left, everything else on the right.
                    final artSize = math.max(120.0, math.min(box.maxHeight - 150, box.maxWidth * 0.42));
                    return Column(children: [
                      _TopBar(track: track),
                      Expanded(
                        child: Row(children: [
                          Expanded(child: Center(child: DiscPlayer(player: player, track: track, size: artSize, glow: accent))),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 520),
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    _TitleRow(track: track),
                                    const SizedBox(height: 14),
                                    _Controls(player: player),
                                    const SizedBox(height: 12),
                                    _ActionRow(player: player, track: track),
                                    const SizedBox(height: 12),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]);
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Column(children: [
                        _TopBar(track: track),
                        Expanded(
                          child: LayoutBuilder(builder: (context, inner) {
                            final artSize = math.min(box.maxWidth - 40, math.max(120.0, math.min(inner.maxHeight * 0.5 - 36, 420.0)));
                            return SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: inner.maxHeight),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    DiscPlayer(player: player, track: track, size: artSize, glow: accent),
                                    _TitleRow(track: track),
                                    _Controls(player: player),
                                    _ActionRow(player: player, track: track),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ));
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Track track;
  const _TopBar({required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Expanded(
          child: Column(children: [
            Text('NOW PLAYING', style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.65))),
            const SizedBox(height: 2),
            Text(
              track.album.isEmpty ? 'Samgeet' : track.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ]),
        ),
        IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => showTrackMenu(context, track)),
      ]),
    );
  }
}

class _TitleRow extends StatelessWidget {
  final Track track;
  const _TitleRow({required this.track});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final fav = lib.isFavorite(track.id);
    final quality = lib.quality == AudioQuality.high ? (track.has320 ? 320 : 160) : lib.quality.kbps;
    final artist = track.artists.where((a) => a.id.isNotEmpty).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                track.title,
                key: ValueKey(track.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontFamily: kDisplay, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6),
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: artist == null
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      openArtist(context, artist);
                    },
              child: Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _Pill(icon: Icons.graphic_eq_rounded, label: '$quality kbps'),
              if (lib.autoplay) const _Pill(icon: Icons.auto_awesome_rounded, label: 'Smart radio'),
              if (context.watch<MoodController>().themed)
                _Pill(icon: context.watch<MoodController>().palette.icon, label: context.watch<MoodController>().palette.label)
              else if (context.watch<MoodController>().songMood != null)
                Pressable(
                  onTap: () => requireSignIn(context, reason: 'Sign in and Samgeet\'s colours will follow the mood of your music.'),
                  child: const _Pill(icon: Icons.lock_outline_rounded, label: 'Mood colours · Sign in'),
                ),
            ]),
          ]),
        ),
        IconButton(
          iconSize: 30,
          onPressed: () => lib.toggleFavorite(track),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
            child: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(fav),
              color: fav ? AppColors.pink : Colors.white,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.85)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85))),
      ]),
    );
  }
}

class _Controls extends StatelessWidget {
  final PlayerController player;
  const _Controls({required this.player});

  @override
  Widget build(BuildContext context) {
    final loop = player.loopMode;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      IconButton(
        iconSize: 26,
        onPressed: player.toggleShuffle,
        icon: Icon(Icons.shuffle_rounded, color: player.shuffle ? AppColors.pink : Colors.white70),
      ),
      IconButton(iconSize: 40, onPressed: player.previous, icon: const Icon(Icons.skip_previous_rounded)),
      _BigPlayButton(player: player),
      IconButton(iconSize: 40, onPressed: player.next, icon: const Icon(Icons.skip_next_rounded)),
      IconButton(
        iconSize: 26,
        onPressed: player.toggleLoop,
        icon: Icon(
          loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
          color: loop == LoopMode.off ? Colors.white70 : AppColors.pink,
        ),
      ),
    ]);
  }
}

class _BigPlayButton extends StatelessWidget {
  final PlayerController player;
  const _BigPlayButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return StreamBuilder<PlayerState>(
      stream: player.player.playerStateStream,
      builder: (_, snap) {
        final st = snap.data;
        final playing = st?.playing ?? false;
        final busy = st?.processingState == ProcessingState.loading || st?.processingState == ProcessingState.buffering;
        return Pressable(
          onTap: player.togglePlay,
          scale: 0.92,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: mood.gradient, boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.65), blurRadius: 30, spreadRadius: 1)]),
            child: Stack(alignment: Alignment.center, children: [
              if (busy && playing) const SizedBox(width: 62, height: 62, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white70)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: RotationTransition(turns: Tween(begin: 0.85, end: 1.0).animate(a), child: c)),
                child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(playing), size: 42, color: Colors.white),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _ActionRow extends StatelessWidget {
  final PlayerController player;
  final Track track;
  const _ActionRow({required this.player, required this.track});

  @override
  Widget build(BuildContext context) {
    final sleepOn = player.hasSleepTimer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Action(icon: Icons.bedtime_outlined, label: 'Sleep', active: sleepOn, onTap: () => showSleepSheet(context)),
        _Action(icon: Icons.lyrics_outlined, label: 'Lyrics', onTap: () => showLyricsSheet(context, track)),
        _Action(icon: Icons.playlist_add_rounded, label: 'Playlist', onTap: () => showPlaylistPicker(context, [track])),
        _Action(icon: Icons.ios_share_rounded, label: 'Share', onTap: () => ShareService.shareTrack(track)),
        _Action(icon: Icons.queue_music_rounded, label: 'Queue', onTap: () => showQueueSheet(context)),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: active ? AppColors.pink : Colors.white.withValues(alpha: 0.85)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: active ? AppColors.pink : Colors.white60)),
        ]),
      ),
    );
  }
}

/// Drag the player down to minimize it back to the mini player.
///
/// Watches raw pointer events rather than competing in the gesture arena, so
/// it works over the whole screen (buttons, artwork, the scroll view) as long
/// as the swipe is mostly downward, the content is scrolled to the top and the
/// listener isn't dragging the seek ring.
class _SwipeDownToMinimize extends StatefulWidget {
  final Widget child;
  const _SwipeDownToMinimize({required this.child});

  @override
  State<_SwipeDownToMinimize> createState() => _SwipeDownToMinimizeState();
}

class _SwipeDownToMinimizeState extends State<_SwipeDownToMinimize> with SingleTickerProviderStateMixin {
  static const _slop = 18.0;

  late final AnimationController _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
    ..addListener(() => setState(() => _dy = _settleFrom * (1 - Curves.easeOutCubic.transform(_settle.value))));
  double _settleFrom = 0;

  double _dy = 0;
  bool _atTop = true;
  int? _pointer;
  Offset _start = Offset.zero;
  bool _engaged = false;
  bool _rejected = false;
  VelocityTracker? _velocity;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _snapBack() {
    if (_dy == 0) return;
    _settleFrom = _dy;
    _settle.forward(from: 0);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return; // a second finger doesn't restart the drag
    _settle.stop();
    _pointer = e.pointer;
    _start = e.position;
    _engaged = false;
    _rejected = !_atTop;
    _velocity = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _rejected) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    if (DiscPlayer.scrubbing.value) {
      _rejected = true;
      _engaged = false;
      _snapBack();
      return;
    }
    final d = e.position - _start;
    if (!_engaged) {
      if (d.distance < _slop) return;
      if (d.dy > 0 && d.dy > d.dx.abs() * 1.4) {
        _engaged = true;
      } else {
        _rejected = true; // sideways swipe (skip song) or an upward scroll
        return;
      }
    }
    setState(() => _dy = math.max(0, d.dy - _slop));
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    if (!_engaged) return;
    _engaged = false;
    final v = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0;
    final h = context.size?.height ?? 800;
    if (_dy > h * 0.22 || (v > 900 && _dy > 40)) {
      Navigator.of(context).maybePop();
    } else {
      _snapBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = math.min(28.0, _dy / 3);
    final progress = (_dy / MediaQuery.sizeOf(context).height).clamp(0.0, 1.0);
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical) _atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 0.5;
          return false;
        },
        child: Stack(children: [
          // While dragging, the app underneath is blurred and dimmed, clearing as the player moves away.
          if (_dy > 0)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16 * (1 - progress), sigmaY: 16 * (1 - progress)),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.45 * (1 - progress))),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(0, _dy),
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              child: widget.child,
            ),
          ),
        ]),
      ),
    );
  }
}
