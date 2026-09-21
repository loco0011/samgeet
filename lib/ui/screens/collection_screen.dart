import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/track_widgets.dart';

/// An album or a curated playlist from the catalogue.
class CollectionScreen extends StatefulWidget {
  final String id;
  final String title;
  final String image;
  final String subtitle;
  final bool isAlbum;

  const CollectionScreen.playlist({super.key, required this.id, required this.title, this.image = '', this.subtitle = ''}) : isAlbum = false;
  const CollectionScreen.album({super.key, required this.id, required this.title, this.image = '', this.subtitle = ''}) : isAlbum = true;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late Future<Collection> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<SaavnApi>();
    _future = widget.isAlbum ? api.album(widget.id) : api.playlist(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Collection>(
      future: _future,
      builder: (context, snap) {
        final c = snap.data;
        final tracks = c?.tracks.where((t) => t.isPlayable).toList() ?? const <Track>[];
        final title = (c?.title.isNotEmpty ?? false) ? c!.title : widget.title;
        final image = (c?.image.isNotEmpty ?? false) ? c!.art(500) : widget.image.replaceAll('150x150', '500x500');
        final minutes = tracks.fold<int>(0, (s, t) => s + t.durationSec) ~/ 60;
        final ctx = title;

        return DetailScaffold(
          title: title,
          image: image,
          subtitle: c == null ? widget.subtitle : '${tracks.length} songs${minutes > 0 ? ' · $minutes min' : ''}${widget.subtitle.isNotEmpty ? '\n${widget.subtitle}' : ''}',
          buttons: tracks.isEmpty
              ? null
              : PlayBar(
                  onPlay: () => context.read<PlayerController>().playTracks(tracks, context: ctx),
                  onShuffle: () => context.read<PlayerController>().playTracks(tracks, context: ctx, shuffleOn: true, start: 0),
                  extra: [
                    RoundIconButton(
                      icon: Icons.playlist_add_rounded,
                      tooltip: 'Save as playlist',
                      onTap: () async {
                        if (!await allowPlaylistSize(context, tracks.length)) return;
                        if (!context.mounted) return;
                        context.read<LibraryStore>().createPlaylist(title, tracks: tracks);
                        toast(context, 'Saved "$title" to your library');
                      },
                    ),
                    RoundIconButton(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: () => sharePlaylistGated(context, title, tracks)),
                  ],
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
            else if (c == null)
              const SliverToBoxAdapter(child: TrackListSkeleton())
            else
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (_, i) => TrackTile(
                  track: tracks[i],
                  number: i + 1,
                  onTap: () => context.read<PlayerController>().playTracks(tracks, start: i, context: ctx),
                ),
              ),
          ],
        );
      },
    );
  }
}
