import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../data/catalog.dart';
import '../../data/track.dart';
import '../mood_theme.dart';
import '../responsive.dart';
import '../theme.dart';
import 'common.dart';

/// Poster card: artwork fills the card and the title is printed on it.
/// Three fit across a phone, so much more music is visible at once.
class PosterCard extends StatelessWidget {
  final String image;
  final String title;
  final String subtitle;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const PosterCard({
    super.key,
    required this.image,
    required this.title,
    required this.width,
    required this.onTap,
    this.subtitle = '',
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final height = Responsive.posterHeight(width);
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      scale: 0.95,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.32), Colors.white.withValues(alpha: 0.04), Colors.white.withValues(alpha: 0.14)],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(fit: StackFit.expand, children: [
            Artwork(image, radius: 0, cacheSize: 420),
            // Scrim so the title is always readable.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x22000000), Color(0xC8000000), Color(0xF505050B)],
                  stops: [0, 0.36, 0.66, 1],
                ),
              ),
            ),
            Positioned(
              left: 9,
              right: 9,
              bottom: 9,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2, letterSpacing: -0.1),
                ),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.68))),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A card for an album / playlist / song / artist. Artists are round with a glowing ring.
class MediaCardTile extends StatelessWidget {
  final String image;
  final String title;
  final String subtitle;
  final double size;
  final bool circle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const MediaCardTile({
    super.key,
    required this.image,
    required this.title,
    required this.onTap,
    this.subtitle = '',
    this.size = 110,
    this.circle = false,
    this.onLongPress,
  });

  factory MediaCardTile.card(MediaCard c, {Key? key, double size = 110, required VoidCallback onTap}) => MediaCardTile(
        key: key,
        image: c.art(500),
        title: c.title,
        subtitle: c.subtitle,
        size: size,
        circle: c.kind == CardKind.artist,
        onTap: onTap,
      );

  factory MediaCardTile.track(Track t, {Key? key, double size = 110, required VoidCallback onTap, VoidCallback? onLongPress}) =>
      MediaCardTile(key: key, image: t.art(500), title: t.title, subtitle: t.artistLine, size: size, onTap: onTap, onLongPress: onLongPress);

  @override
  Widget build(BuildContext context) {
    if (!circle) {
      return PosterCard(image: image, title: title, subtitle: subtitle, width: size, onTap: onTap, onLongPress: onLongPress);
    }
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: moodPalette(context).gradient,
              boxShadow: [BoxShadow(color: moodPalette(context).accent.withValues(alpha: 0.6), blurRadius: 16)],
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
              child: Artwork(image, size: size - 9, circle: true, cacheSize: 300),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 11.5),
          ),
        ]),
      ),
    );
  }
}

/// A horizontally scrolling row of widgets that fade/slide in.
class Shelf extends StatelessWidget {
  final double height;
  final int count;
  final Widget Function(BuildContext, int) itemBuilder;
  final double gap;
  const Shelf({super.key, required this.height, required this.count, required this.itemBuilder, this.gap = 10});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: count,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (c, i) {
          final w = itemBuilder(c, i);
          if (i > 6) return w;
          return w.animate().fadeIn(duration: 350.ms, delay: (55 * i).ms).slideX(begin: 0.14, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}

class CardShelf extends StatelessWidget {
  final List<MediaCard> cards;
  final void Function(MediaCard) onTap;
  final double? size;
  const CardShelf({super.key, required this.cards, required this.onTap, this.size});

  @override
  Widget build(BuildContext context) {
    final w = size ?? Responsive.posterWidth(MediaQuery.sizeOf(context).width);
    final circle = cards.isNotEmpty && cards.every((c) => c.kind == CardKind.artist);
    return Shelf(
      height: circle ? w + 34 : Responsive.posterHeight(w) + 6,
      count: cards.length,
      itemBuilder: (_, i) => MediaCardTile.card(cards[i], size: w, onTap: () => onTap(cards[i])),
    );
  }
}

class TrackShelf extends StatelessWidget {
  final List<Track> tracks;
  final void Function(Track, int) onTap;
  final void Function(Track)? onLongPress;
  const TrackShelf({super.key, required this.tracks, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final w = Responsive.posterWidth(MediaQuery.sizeOf(context).width);
    return Shelf(
      height: Responsive.posterHeight(w) + 6,
      count: tracks.length,
      itemBuilder: (_, i) => MediaCardTile.track(tracks[i], size: w, onTap: () => onTap(tracks[i], i), onLongPress: onLongPress == null ? null : () => onLongPress!(tracks[i])),
    );
  }
}

class ArtistShelf extends StatelessWidget {
  final List<ArtistRef> artists;
  final void Function(ArtistRef) onTap;
  final double size;
  const ArtistShelf({super.key, required this.artists, required this.onTap, this.size = 92});

  @override
  Widget build(BuildContext context) {
    return Shelf(
      height: size + 34,
      gap: 14,
      count: artists.length,
      itemBuilder: (_, i) => MediaCardTile(
        image: artists[i].image.replaceAll('50x50', '250x250').replaceAll('150x150', '250x250'),
        title: artists[i].name,
        size: size,
        circle: true,
        onTap: () => onTap(artists[i]),
      ),
    );
  }
}

/// A 3-across grid of poster cards (non-scrolling; put it in a list).
class PosterGrid extends StatelessWidget {
  final List<MediaCard> cards;
  final void Function(MediaCard) onTap;
  const PosterGrid({super.key, required this.cards, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(builder: (context, box) {
        final cols = (box.maxWidth / 130).floor().clamp(3, 8);
        final w = (box.maxWidth - (cols - 1) * 10) / cols;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1 / 1.28),
          itemCount: cards.length,
          itemBuilder: (_, i) => MediaCardTile.card(cards[i], size: w, onTap: () => onTap(cards[i]))
              .animate()
              .fadeIn(duration: 320.ms, delay: (45 * (i % 9)).ms)
              .scale(begin: const Offset(0.92, 0.92), duration: 360.ms, curve: Curves.easeOutBack),
        );
      }),
    );
  }
}

/// Swipeable feature cards with a parallax album cover. Slides on its own every
/// few seconds (slowly), loops forever and stops while you touch it.
class HeroCarousel extends StatefulWidget {
  final List<MediaCard> cards;
  final void Function(MediaCard) onTap;
  final String label;
  const HeroCarousel({super.key, required this.cards, required this.onTap, this.label = 'TRENDING'});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  static const _pause = Duration(seconds: 3);
  static const _glide = Duration(milliseconds: 1100);

  PageController? _pager;
  double _fraction = 0.78;
  int _page = 0; // raw page; the card shown is _page % length
  bool _initialised = false;
  bool _touching = false;
  Timer? _timer;

  PageController get _controller => _pager!;
  int get _count => math.min(widget.cards.length, 8);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Narrower cards on wide screens so the artwork isn't stretched and cropped.
    final f = MediaQuery.sizeOf(context).width >= 700 ? 0.38 : 0.78;
    if (!_initialised) {
      // Start in the middle of a huge range so you can swipe either way, forever.
      _page = _count * 500;
      _initialised = true;
    }
    if (_pager == null || f != _fraction) {
      _pager?.dispose();
      _fraction = f;
      _pager = PageController(viewportFraction: f, initialPage: _page);
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer(_pause, _advance);
  }

  void _advance() {
    if (!mounted) return;
    final settled = _controller.hasClients && !_controller.position.isScrollingNotifier.value;
    // Don't slide while a finger is down, the tab is hidden, or the OS asks for less motion.
    if (_touching || !settled || !TickerMode.valuesOf(context).enabled || MediaQuery.disableAnimationsOf(context)) {
      _schedule();
      return;
    }
    _controller.animateToPage(_page + 1, duration: _glide, curve: Curves.easeInOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards.take(8).toList();
    final n = cards.length;
    final index = n == 0 ? 0 : _page % n;
    final palette = moodPalette(context);
    return Column(children: [
      Listener(
        onPointerDown: (_) {
          _touching = true;
          _timer?.cancel();
        },
        onPointerUp: (_) {
          _touching = false;
          _schedule();
        },
        onPointerCancel: (_) {
          _touching = false;
          _schedule();
        },
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            if (!_touching) _schedule();
            return false;
          },
          child: SizedBox(
            height: 176,
            child: PageView.builder(
              controller: _controller,
              clipBehavior: Clip.none,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final page = _controller.hasClients && _controller.position.haveDimensions ? (_controller.page ?? _page.toDouble()) : _page.toDouble();
                  final delta = (page - i).clamp(-1.0, 1.0);
                  final card = cards[i % n];
                  return Opacity(
                    opacity: 1 - 0.4 * delta.abs(),
                    child: Transform.scale(
                      scale: 1 - 0.08 * delta.abs(),
                      child: _HeroCard(card: card, parallax: delta, label: widget.label, onTap: () => widget.onTap(card)),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < n; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 6,
            height: 5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: i == index ? palette.gradient : null,
              color: i == index ? null : Colors.white.withValues(alpha: 0.22),
              boxShadow: i == index ? [BoxShadow(color: palette.accent.withValues(alpha: 0.6), blurRadius: 8)] : null,
            ),
          ),
      ]),
    ]);
  }
}

class _HeroCard extends StatelessWidget {
  final MediaCard card;
  final double parallax;
  final String label;
  final VoidCallback onTap;
  const _HeroCard({required this.card, required this.parallax, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kind = switch (card.kind) {
      CardKind.album => 'ALBUM',
      CardKind.playlist => 'PLAYLIST',
      CardKind.chart => 'CHART',
      CardKind.artist => 'ARTIST',
      _ => label,
    };
    final palette = moodPalette(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        child: Container(
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.04), palette.accent.withValues(alpha: 0.45)]),
            boxShadow: [BoxShadow(color: palette.accent.withValues(alpha: 0.28), blurRadius: 20, offset: const Offset(0, 9))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(23),
            child: Stack(fit: StackFit.expand, children: [
              Transform.translate(
                offset: Offset(-parallax * 34, 0),
                child: Transform.scale(
                  scale: 1.18,
                  child: CachedNetworkImage(imageUrl: card.art(500), fit: BoxFit.cover, memCacheWidth: 700, errorWidget: (_, _, _) => Container(decoration: const BoxDecoration(gradient: AppColors.gradient))),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33000000), Color(0x00000000), Color(0xB005050B), Color(0xF005050B)], stops: [0, 0.28, 0.68, 1]),
                ),
              ),
              Positioned(
                top: 11,
                left: 11,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: palette.light, boxShadow: [BoxShadow(color: palette.light, blurRadius: 5)])),
                    const SizedBox(width: 5),
                    Text(kind, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
                  ]),
                ),
              ),
              Positioned(
                left: 13,
                right: 60,
                bottom: 12,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kDisplay, fontSize: 17, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.4)),
                  if (card.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(card.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.72))),
                    ),
                ]),
              ),
              Positioned(
                right: 11,
                bottom: 11,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: palette.gradient, boxShadow: [BoxShadow(color: palette.accent.withValues(alpha: 0.55), blurRadius: 12)]),
                  child: const Icon(Icons.play_arrow_rounded, size: 24),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Glass tile for moods, eras, languages and genres: a glowing gradient icon on frosted glass.
class CategoryTile extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  final double? width;
  final double height;
  const CategoryTile({super.key, required this.category, required this.onTap, this.width, this.height = 100});

  @override
  Widget build(BuildContext context) {
    final c = category.colors;
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.first.withValues(alpha: 0.65), Colors.white.withValues(alpha: 0.05), c.last.withValues(alpha: 0.35)]),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.first.withValues(alpha: 0.24), AppColors.bg.withValues(alpha: 0.62), c.last.withValues(alpha: 0.14)]),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
                boxShadow: [BoxShadow(color: c.first.withValues(alpha: 0.55), blurRadius: 14)],
              ),
              child: Icon(category.icon, size: 18),
            ),
            const Spacer(),
            Text(category.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: -0.2)),
            if (category.subtitle.isNotEmpty)
              Text(category.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: AppColors.muted)),
          ]),
        ),
      ),
    );
  }
}

/// Grid of category tiles (three across on a phone).
class CategoryGrid extends StatelessWidget {
  final List<Category> items;
  final void Function(Category) onTap;
  final double tileHeight;
  const CategoryGrid({super.key, required this.items, required this.onTap, this.tileHeight = 100});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, box) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Responsive.tileColumns(box.maxWidth),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: tileHeight,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => CategoryTile(category: items[i], onTap: () => onTap(items[i]), height: tileHeight)
              .animate()
              .fadeIn(duration: 300.ms, delay: (30 * (i % 12)).ms)
              .scale(begin: const Offset(0.92, 0.92), duration: 340.ms, curve: Curves.easeOutBack),
        ),
      ),
    );
  }
}

/// Horizontal strip of category tiles.
class CategoryStrip extends StatelessWidget {
  final List<Category> items;
  final void Function(Category) onTap;
  const CategoryStrip({super.key, required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = Responsive.posterWidth(MediaQuery.sizeOf(context).width);
    return Shelf(
      height: 100,
      count: items.length,
      itemBuilder: (_, i) => CategoryTile(category: items[i], width: w, height: 100, onTap: () => onTap(items[i])),
    );
  }
}
