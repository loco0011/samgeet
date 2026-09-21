import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';
import 'dominant_color.dart';

/// Shared layout for album / playlist / artist / category pages:
/// a collapsing colourful header, an action bar, then slivers.
class DetailScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String image;
  final bool circleArt;
  final List<Color>? colors;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? buttons;
  final List<Widget> slivers;
  /// Builds custom artwork for a given square size (used by playlists).
  final Widget Function(double size)? artBuilder;

  const DetailScaffold({
    super.key,
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.circleArt = false,
    this.colors,
    this.icon,
    this.actions = const [],
    this.buttons,
    this.slivers = const [],
    this.artBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // Scale the header to the screen so it never swallows a short (landscape) display.
    final expanded = (MediaQuery.sizeOf(context).height * 0.38).clamp(220.0, 340.0);
    final art = (expanded - 130).clamp(110.0, 220.0);

    Widget scaffold(Color accent, Color accent2) => Scaffold(
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: expanded,
                backgroundColor: Color.lerp(accent2, AppColors.bg, 0.55),
                surfaceTintColor: Colors.transparent,
                actions: actions,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsetsDirectional.only(start: 56, end: 56, bottom: 14),
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [accent, Color.lerp(accent2, AppColors.bg, 0.6)!, AppColors.bg],
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: EdgeInsets.only(top: expanded > 260 ? 40 : 24, bottom: expanded > 260 ? 50 : 44),
                        child: Center(
                          child: artBuilder?.call(art) ??
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: circleArt ? null : BorderRadius.circular(22),
                                  shape: circleArt ? BoxShape.circle : BoxShape.rectangle,
                                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 14))],
                                ),
                                child: image.isNotEmpty
                                    ? Artwork(image, size: art, radius: 22, circle: circleArt, cacheSize: 500)
                                    : Container(
                                        width: art,
                                        height: art,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(22),
                                          gradient: LinearGradient(colors: colors ?? moodPalette(context).colors),
                                        ),
                                        child: Icon(icon ?? Icons.music_note_rounded, size: art * 0.42, color: Colors.white.withValues(alpha: 0.9)),
                                      ),
                              ).animate().fadeIn(duration: 450.ms).scale(begin: const Offset(0.9, 0.9), duration: 500.ms, curve: Curves.easeOutBack),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (subtitle.isNotEmpty || buttons != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.4)),
                      if (buttons != null) ...[const SizedBox(height: 14), buttons!],
                    ]),
                  ),
                ),
              ...slivers,
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );

    if (colors != null && image.isEmpty) return scaffold(colors!.first, colors!.last);
    return DominantColorBuilder(url: image, builder: (_, c) => scaffold(c, c));
  }
}

/// Play / Shuffle plus extra round icon buttons.
class PlayBar extends StatelessWidget {
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final List<Widget> extra;
  const PlayBar({super.key, this.onPlay, this.onShuffle, this.extra = const []});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      GradientButton(label: 'Play', icon: Icons.play_arrow_rounded, onTap: onPlay),
      const SizedBox(width: 12),
      Pressable(
        onTap: onShuffle,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(30), border: Border.all(color: AppColors.outline)),
          child: const Row(children: [Icon(Icons.shuffle_rounded, size: 20), SizedBox(width: 8), Text('Shuffle', style: TextStyle(fontWeight: FontWeight.w700))]),
        ),
      ),
      const Spacer(),
      ...extra,
    ]);
  }
}

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? color;
  const RoundIconButton({super.key, required this.icon, required this.onTap, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Pressable(
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.outline)),
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}
