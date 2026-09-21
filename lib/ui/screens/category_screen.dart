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
      final results = await Future.wait([
        api.searchSongs(c.songQuery ?? c.query, n: 40),
        api.searchPlaylists(c.query, n: 12).catchError((_) => <MediaCard>[]),
      ]);
      final songs = (results[0] as List<Track>).where((t) => t.isPlayable).toList();
      return _CategoryData(songs, results[1] as List<MediaCard>);
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
