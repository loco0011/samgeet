import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/shelves.dart';
import '../widgets/track_widgets.dart';

class ArtistScreen extends StatefulWidget {
  final ArtistRef artist;
  const ArtistScreen({super.key, required this.artist});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<ArtistPage> _future;
  bool _bioOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<SaavnApi>();
    _future = () async {
      var id = widget.artist.id;
      // Some songs only carry an artist name — look the artist up first.
      if (id.isEmpty) {
        final found = await api.searchArtists(widget.artist.name, n: 3);
        if (found.isEmpty) throw ApiException('Couldn\'t find ${widget.artist.name}');
        id = found.first.id;
      }
      return api.artist(id);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    return FutureBuilder<ArtistPage>(
      future: _future,
      builder: (context, snap) {
        final page = snap.data;
        final artist = page?.artist ?? widget.artist;
        final image = (page?.artist.image.isNotEmpty ?? false ? page!.artist.image : widget.artist.image).replaceAll('150x150', '500x500').replaceAll('50x50', '500x500');
        final songs = page?.topSongs.where((t) => t.isPlayable).toList() ?? const <Track>[];
        final following = lib.isFollowing(artist);
        final ctx = artist.name;

        return DetailScaffold(
          title: artist.name,
          image: image,
          circleArt: true,
          subtitle: page == null ? '' : (page.followers.isEmpty ? '' : '${page.followers} fans'),
          buttons: Row(children: [
            if (songs.isNotEmpty) ...[
              GradientButton(label: 'Play', icon: Icons.play_arrow_rounded, onTap: () => context.read<PlayerController>().playTracks(songs, context: ctx)),
              const SizedBox(width: 10),
              RoundIconButton(icon: Icons.shuffle_rounded, tooltip: 'Shuffle', onTap: () => context.read<PlayerController>().playTracks(songs, context: ctx, shuffleOn: true)),
            ],
            const Spacer(),
            Pressable(
              onTap: () {
                lib.toggleFollow(artist);
                toast(context, following ? 'Unfollowed ${artist.name}' : 'Following ${artist.name} — you\'ll hear more of them');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: following ? AppColors.pink.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: following ? AppColors.pink : Colors.white38),
                ),
                child: Text(following ? 'Following' : 'Follow', style: TextStyle(fontWeight: FontWeight.w700, color: following ? AppColors.pink : Colors.white)),
              ),
            ),
          ]),
          slivers: [
            if (snap.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Can\'t load this artist',
                  message: '${snap.error}',
                  action: GradientButton(label: 'Try again', compact: true, onTap: () => setState(_load)),
                ),
              )
            else if (page == null)
              const SliverToBoxAdapter(child: TrackListSkeleton())
            else ...[
              const SliverToBoxAdapter(child: SectionHeader('Popular')),
              SliverList.builder(
                itemCount: songs.length > 10 ? 10 : songs.length,
                itemBuilder: (_, i) => TrackTile(
                  track: songs[i],
                  number: i + 1,
                  onTap: () => context.read<PlayerController>().playTracks(songs, start: i, context: ctx),
                ),
              ),
              if (songs.length > 10)
                SliverToBoxAdapter(
                  child: Center(
                    child: TextButton(
                      onPressed: () => pushPage(context, _AllSongsScreen(title: artist.name, songs: songs)),
                      child: const Text('See all songs'),
                    ),
                  ),
                ),
              if (page.albums.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader('Albums')),
                SliverToBoxAdapter(child: CardShelf(cards: page.albums, onTap: (c) => openCard(context, c))),
              ],
              if (page.similar.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader('Fans also like')),
                SliverToBoxAdapter(child: ArtistShelf(artists: page.similar, onTap: (a) => openArtist(context, a))),
              ],
              if (page.bio.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionHeader('About')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: GestureDetector(
                      onTap: () => setState(() => _bioOpen = !_bioOpen),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        alignment: Alignment.topCenter,
                        child: Text(
                          page.bio,
                          maxLines: _bioOpen ? null : 4,
                          overflow: _bioOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.muted, height: 1.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _AllSongsScreen extends StatelessWidget {
  final String title;
  final List<Track> songs;
  const _AllSongsScreen({required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.builder(
        itemCount: songs.length,
        itemBuilder: (_, i) => TrackTile(
          track: songs[i],
          number: i + 1,
          onTap: () => context.read<PlayerController>().playTracks(songs, start: i, context: title),
        ),
      ),
    );
  }
}
