import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/shelves.dart';
import '../widgets/track_widgets.dart';

/// One song list for a category: the hand-picked songs first, then the
/// searches taken in turns (so extra singers are spread through the list, not
/// piled at the end). Drops re-uploads of the same song and, for
/// [Category.strictLanguage], songs in other languages, unless that would
/// leave the list nearly empty.
List<Track> mixCategorySongs(Category c, {List<Track> picks = const [], required List<List<Track>> searches}) {
  final ids = <String>{};
  final names = <String>{};
  final out = <Track>[];
  void add(Track t) {
    if (!t.isPlayable) return;
    if (ids.add(t.id) && names.add(t.sameSongKey)) out.add(t);
  }

  picks.forEach(add);
  final longest = searches.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (var i = 0; i < longest; i++) {
    for (final l in searches) {
      if (i < l.length) add(l[i]);
    }
  }
  if (!c.strictLanguage) return out;
  final inLanguage = out.where((t) => t.language == c.language).toList();
  return inLanguage.length >= 8 ? inLanguage : out;
}

class _CategoryData {
  final List<Track> songs;
  final List<MediaCard> playlists;
  const _CategoryData(this.songs, this.playlists);
}

/// A mood / era / language / genre page: curated playlists + top songs.
class CategoryScreen extends StatefulWidget {
  final Category category;
  const CategoryScreen({super.key, required this.category});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late Future<_CategoryData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<SaavnApi>();
    final c = widget.category;
    _future = () async {
      final queries = c.songQueries;
      final results = await Future.wait<List<Object>>([
        api.searchPlaylists(c.query, n: 12).catchError((_) => <MediaCard>[]),
        // Hand-picked songs: the best match for each phrase, skipping any the catalogue lacks.
        Future.wait(c.picks.map((p) => api.findSongs(p, n: 3).then((r) => r.songs).catchError((_) => <Track>[])))
            .then((found) => [for (final l in found) ...l.where((t) => t.isPlayable).take(1)]),
        // The main search must work; the extra ones only widen the list.
        api.searchSongs(queries.first, n: 40),
        for (final q in queries.skip(1)) api.searchSongs(q, n: 25).catchError((_) => <Track>[]),
      ]);
      final songs = mixCategorySongs(
        c,
        picks: results[1].cast<Track>(),
        searches: [for (final r in results.skip(2)) r.cast<Track>()],
      );
      return _CategoryData(songs, c.playlists ? results[0].cast<MediaCard>() : const []);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final ctx = c.songQuery ?? c.query;
    return FutureBuilder<_CategoryData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        final songs = data?.songs ?? const <Track>[];
        return DetailScaffold(
          title: c.title,
          colors: c.colors,
          icon: c.icon,
          subtitle: c.subtitle,
          buttons: songs.isEmpty
              ? null
              : PlayBar(
                  onPlay: () => context.read<PlayerController>().playTracks(songs, context: ctx),
                  onShuffle: () => context.read<PlayerController>().playTracks(songs, context: ctx, shuffleOn: true),
                ),
          slivers: [
            if (snap.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Can\'t load this right now',
                  message: '${snap.error}',
                  action: GradientButton(label: 'Try again', compact: true, onTap: () => setState(_load)),
                ),
              )
            else if (data == null)
              const SliverToBoxAdapter(child: TrackListSkeleton())
            else ...[
              if (data.playlists.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader('Curated playlists')),
                SliverToBoxAdapter(child: CardShelf(cards: data.playlists, onTap: (card) => openCard(context, card))),
              ],
              const SliverToBoxAdapter(child: SectionHeader('Top songs')),
              SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (_, i) => TrackTile(
                  track: songs[i],
                  number: i + 1,
                  onTap: () => context.read<PlayerController>().playTracks(songs, start: i, context: ctx),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
