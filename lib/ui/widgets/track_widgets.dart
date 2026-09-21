import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/share_service.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';

/// A song row: artwork, title, artists, like + menu.
class TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  final int? number;
  final bool showLike;
  final UserPlaylist? inPlaylist;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.number,
    this.showLike = false,
    this.inPlaylist,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<PlayerController, bool>((p) => p.current?.id == track.id);
    final playing = context.select<PlayerController, bool>((p) => p.current?.id == track.id && p.isPlaying);
    final lib = context.watch<LibraryStore>();

    return InkWell(
      onTap: onTap,
      onLongPress: () => showTrackMenu(context, track, inPlaylist: inPlaylist),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(children: [
          if (number != null)
            SizedBox(
              width: 28,
              child: isCurrent
                  ? EqualizerBars(animate: playing, size: 16)
                  : Text('$number', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
          Stack(alignment: Alignment.center, children: [
            Artwork(track.image, size: 54, radius: 12, cacheSize: 150),
            if (number == null && isCurrent)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                child: Center(child: EqualizerBars(animate: playing, color: Colors.white)),
              ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: isCurrent ? AppColors.pink : Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                track.artistLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ]),
          ),
          if (showLike)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => lib.toggleFavorite(track),
              icon: Icon(
                lib.isFavorite(track.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: lib.isFavorite(track.id) ? AppColors.pink : AppColors.muted,
                size: 22,
              ),
            ),
          ?trailing,
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.muted),
            onPressed: () => showTrackMenu(context, track, inPlaylist: inPlaylist),
          ),
        ]),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuItem(this.icon, this.label, this.onTap, {this.color});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color ?? Colors.white70),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      onTap: onTap,
    );
  }
}

/// The long-press / "⋮" menu for a song.
Future<void> showTrackMenu(BuildContext context, Track t, {UserPlaylist? inPlaylist}) {
  final player = context.read<PlayerController>();
  final lib = context.read<LibraryStore>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Artwork(t.image, size: 60, radius: 14, cacheSize: 200),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 3),
                  Text(t.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
          const Divider(height: 1),
          ListenableBuilder(
            listenable: lib,
            builder: (_, _) => _MenuItem(
              lib.isFavorite(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              lib.isFavorite(t.id) ? 'Remove from liked songs' : 'Add to liked songs',
              () {
                lib.toggleFavorite(t);
                Navigator.of(sheetContext).pop();
              },
              color: lib.isFavorite(t.id) ? AppColors.pink : null,
            ),
          ),
          _MenuItem(Icons.playlist_add_rounded, 'Add to playlist', () {
            Navigator.of(sheetContext).pop();
            showPlaylistPicker(context, [t]);
          }),
          _MenuItem(Icons.queue_play_next_rounded, 'Play next', () {
            Navigator.of(sheetContext).pop();
            player.playNext(t);
          }),
          _MenuItem(Icons.playlist_play_rounded, 'Add to queue', () {
            Navigator.of(sheetContext).pop();
            player.addToQueue(t);
          }),
          _MenuItem(Icons.sensors_rounded, 'Start song radio', () {
            Navigator.of(sheetContext).pop();
            player.startRadio(t);
          }),
          if (t.artists.any((a) => a.id.isNotEmpty))
            _MenuItem(Icons.person_rounded, 'Go to ${t.artists.firstWhere((a) => a.id.isNotEmpty).name}', () {
              Navigator.of(sheetContext).pop();
              openArtist(context, t.artists.firstWhere((a) => a.id.isNotEmpty));
            }),
          if (t.albumId.isNotEmpty)
            _MenuItem(Icons.album_rounded, 'Go to album', () {
              Navigator.of(sheetContext).pop();
              openAlbum(context, t.albumId, t.album);
            }),
          _MenuItem(Icons.ios_share_rounded, 'Share', () {
            Navigator.of(sheetContext).pop();
            ShareService.shareTrack(t);
          }),
          if (inPlaylist != null)
            _MenuItem(Icons.remove_circle_outline_rounded, 'Remove from this playlist', () {
              lib.removeFromPlaylist(inPlaylist.id, t.id);
              Navigator.of(sheetContext).pop();
            }, color: Colors.redAccent),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}

/// Choose a playlist to add songs to (or create a new one).
Future<void> showPlaylistPicker(BuildContext context, List<Track> tracks) {
  final lib = context.read<LibraryStore>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: ListenableBuilder(
          listenable: lib,
          builder: (_, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Row(children: [
                const Expanded(child: Text('Add to playlist', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
                GradientButton(
                  label: 'New',
                  icon: Icons.add_rounded,
                  compact: true,
                  onTap: () async {
                    final created = await showCreatePlaylistDialog(sheetContext, tracks: tracks);
                    if (created != null && sheetContext.mounted) Navigator.of(sheetContext).pop();
                  },
                ),
              ]),
            ),
            Flexible(
              child: lib.playlists.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No playlists yet.\nTap "New" to create your first one.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: lib.playlists.length,
                      itemBuilder: (_, i) {
                        final p = lib.playlists[i];
                        return ListTile(
                          leading: PlaylistCover(playlist: p, size: 48),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(plural(p.tracks.length, 'song'), style: const TextStyle(color: AppColors.muted)),
                          onTap: () async {
                            final fresh = tracks.where((t) => !p.tracks.any((x) => x.id == t.id)).length;
                            if (!await allowPlaylistSize(sheetContext, p.tracks.length + fresh)) return;
                            final added = lib.addToPlaylist(p.id, tracks);
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                            toast(context, added == 0 ? 'Already in "${p.name}"' : 'Added to "${p.name}"');
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    ),
  );
}

Future<UserPlaylist?> showCreatePlaylistDialog(BuildContext context, {List<Track> tracks = const [], String initial = ''}) async {
  final lib = context.read<LibraryStore>();
  if (!await allowPlaylistSize(context, tracks.length)) return null;
  if (!context.mounted) return null;
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New playlist', style: TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Give it a name'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Create'),
        ),
      ],
    ),
  );
  if (name == null) return null;
  final p = lib.createPlaylist(name, tracks: tracks);
  if (context.mounted) toast(context, tracks.isEmpty ? 'Created "${p.name}"' : 'Added to new playlist "${p.name}"');
  return p;
}

/// Auto-collage cover for a user playlist.
class PlaylistCover extends StatelessWidget {
  final UserPlaylist playlist;
  final double size;
  final double radius;
  const PlaylistCover({super.key, required this.playlist, this.size = 56, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final covers = playlist.covers;
    Widget child;
    if (covers.isEmpty) {
      child = Container(
        decoration: const BoxDecoration(gradient: AppColors.gradient),
        alignment: Alignment.center,
        child: Icon(Icons.queue_music_rounded, size: size * 0.45, color: Colors.white),
      );
    } else if (covers.length < 4) {
      child = Artwork(covers.first, size: size, radius: 0, cacheSize: 300);
    } else {
      child = GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        children: [for (final c in covers) Artwork(c, radius: 0, cacheSize: 150)],
      );
    }
    return SizedBox(width: size, height: size, child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child));
  }
}
