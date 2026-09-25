import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../data/deep_link.dart';
import '../../data/library_store.dart';
import '../../data/saavn_api.dart';
import '../../data/share_service.dart';
import '../../player/player_controller.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/glass.dart';
import 'sign_in_screen.dart';
import '../widgets/shelves.dart';
import '../widgets/track_widgets.dart';

enum _Tab { playlists, liked, artists, history }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Tab _tab = _Tab.playlists;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    const labels = {_Tab.playlists: 'Playlists', _Tab.liked: 'Liked', _Tab.artists: 'Artists', _Tab.history: 'History'};

    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
          child: Row(children: [
            const Expanded(child: Text('Your library', style: TextStyle(fontFamily: kDisplay, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1))),
            IconButton(tooltip: lib.signedIn ? 'Your profile' : 'Sign in', icon: Icon(lib.signedIn ? Icons.account_circle_rounded : Icons.account_circle_outlined), onPressed: () => pushPage(context, const SignInScreen())),
            IconButton(tooltip: 'Import playlist', icon: const Icon(Icons.download_rounded), onPressed: () => showImportDialog(context)),
            IconButton(tooltip: 'New playlist', icon: const Icon(Icons.add_rounded, size: 28), onPressed: () => showCreatePlaylistDialog(context)),
          ]),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              for (final t in _Tab.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassChip(label: labels[t]!, selected: _tab == t, onTap: () => setState(() => _tab = t)),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            layoutBuilder: currentOnlyLayout,
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: switch (_tab) {
                _Tab.playlists => _PlaylistsTab(lib: lib, onLiked: () => setState(() => _tab = _Tab.liked)),
                _Tab.liked => _LikedTab(lib: lib),
                _Tab.artists => _ArtistsTab(lib: lib),
                _Tab.history => _HistoryTab(lib: lib),
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _PlaylistsTab extends StatelessWidget {
  final LibraryStore lib;
  final VoidCallback onLiked;
  const _PlaylistsTab({required this.lib, required this.onLiked});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        onTap: onLiked,
        leading: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: moodPalette(context).colors)),
          child: const Icon(Icons.favorite_rounded),
        ),
        title: const Text('Liked songs', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(plural(lib.favorites.length, 'song'), style: const TextStyle(color: AppColors.muted)),
      ),
      if (lib.playlists.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: EmptyState(
            icon: Icons.queue_music_rounded,
            title: 'No playlists yet',
            message: 'Create your own, or import one a friend shared with you.',
            action: Row(mainAxisSize: MainAxisSize.min, children: [
              GradientButton(label: 'Create', icon: Icons.add_rounded, compact: true, onTap: () => showCreatePlaylistDialog(context)),
              const SizedBox(width: 10),
              OutlinedButton.icon(onPressed: () => showImportDialog(context), icon: const Icon(Icons.download_rounded), label: const Text('Import')),
            ]),
          ),
        )
      else
        for (var i = 0; i < lib.playlists.length; i++)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            onTap: () => pushPage(context, UserPlaylistScreen(playlistId: lib.playlists[i].id)),
            leading: PlaylistCover(playlist: lib.playlists[i], size: 56),
            title: Text(lib.playlists[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(plural(lib.playlists[i].tracks.length, 'song'), style: const TextStyle(color: AppColors.muted)),
            trailing: IconButton(
              icon: const Icon(Icons.ios_share_rounded, color: AppColors.muted),
              onPressed: () => sharePlaylistGated(context, lib.playlists[i].name, lib.playlists[i].tracks),
            ),
          ).animate().fadeIn(delay: (40 * i).ms, duration: 300.ms).slideX(begin: 0.06, end: 0),
    ]);
  }
}

class _LikedTab extends StatelessWidget {
  final LibraryStore lib;
  const _LikedTab({required this.lib});

  @override
  Widget build(BuildContext context) {
    final songs = lib.favorites;
    if (songs.isEmpty) {
      return const EmptyState(icon: Icons.favorite_border_rounded, title: 'No liked songs yet', message: 'Tap the heart on any song to save it here. The more you like, the better your recommendations get.');
    }
    final player = context.read<PlayerController>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: songs.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: PlayBar(
              onPlay: () => player.playTracks(songs, context: 'liked songs'),
              onShuffle: () => player.playTracks(songs, shuffleOn: true, context: 'liked songs'),
              extra: [RoundIconButton(icon: Icons.ios_share_rounded, onTap: () => sharePlaylistGated(context, 'My liked songs', songs))],
            ),
          );
        }
        final t = songs[i - 1];
        return TrackTile(track: t, showLike: true, onTap: () => player.playTracks(songs, start: i - 1));
      },
    );
  }
}

class _ArtistsTab extends StatelessWidget {
  final LibraryStore lib;
  const _ArtistsTab({required this.lib});

  @override
  Widget build(BuildContext context) {
    final artists = lib.followedArtists;
    if (artists.isEmpty) {
      return const EmptyState(icon: Icons.person_outline_rounded, title: 'No favourite singers yet', message: 'Open an artist and tap Follow. Followed artists shape your recommendations.');
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, crossAxisSpacing: 14, mainAxisSpacing: 18, childAspectRatio: 0.74),
      itemCount: artists.length,
      itemBuilder: (_, i) => LayoutBuilder(
        builder: (_, box) => MediaCardTile(
          image: artists[i].image.replaceAll('50x50', '250x250').replaceAll('150x150', '250x250'),
          title: artists[i].name,
          size: box.maxWidth,
          circle: true,
          onTap: () => openArtist(context, artists[i]),
        ),
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final LibraryStore lib;
  const _HistoryTab({required this.lib});

  @override
  Widget build(BuildContext context) {
    final songs = lib.history;
    if (songs.isEmpty) {
      return const EmptyState(icon: Icons.history_rounded, title: 'Nothing played yet', message: 'Songs you listen to will show up here.');
    }
    final player = context.read<PlayerController>();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: songs.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(children: [
              Text('Recently played · ${songs.length}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: lib.clearHistory, child: const Text('Clear')),
            ]),
          );
        }
        return TrackTile(track: songs[i - 1], showLike: true, onTap: () => player.playTracks(songs, start: i - 1));
      },
    );
  }
}

// ---------------------------------------------------------------------------

/// Your own playlist: play, reorder, rename, share, delete.
class UserPlaylistScreen extends StatelessWidget {
  final String playlistId;
  const UserPlaylistScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final p = lib.playlists.where((x) => x.id == playlistId).firstOrNull;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.delete_outline_rounded, title: 'This playlist was deleted'));
    }
    final player = context.read<PlayerController>();
    final tracks = p.tracks;
    final minutes = tracks.fold<int>(0, (s, t) => s + t.durationSec) ~/ 60;

    return DetailScaffold(
      title: p.name,
      subtitle: '${plural(tracks.length, 'song')}${minutes > 0 ? ' · $minutes min' : ''}',
      artBuilder: (size) => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 14))]),
        child: PlaylistCover(playlist: p, size: size, radius: 22),
      ),
      colors: moodPalette(context).colors,
      actions: [
        PopupMenuButton<String>(
          color: AppColors.surface2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (v) async {
            if (v == 'rename') {
              final c = TextEditingController(text: p.name);
              final name = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Rename playlist'),
                  content: TextField(controller: c, autofocus: true, onSubmitted: (s) => Navigator.pop(ctx, s)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
                  ],
                ),
              );
              if (name != null) lib.renamePlaylist(p.id, name);
            } else if (v == 'share') {
              sharePlaylistGated(context, p.name, p.tracks);
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Delete "${p.name}"?'),
                  content: const Text('The songs stay in the catalogue — only this playlist is removed.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                lib.deletePlaylist(p.id);
                Navigator.of(context).pop();
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.redAccent))),
          ],
        ),
      ],
      buttons: tracks.isEmpty
          ? null
          : PlayBar(
              onPlay: () => player.playTracks(tracks, context: p.name),
              onShuffle: () => player.playTracks(tracks, context: p.name, shuffleOn: true),
              extra: [RoundIconButton(icon: Icons.ios_share_rounded, tooltip: 'Share', onTap: () => sharePlaylistGated(context, p.name, p.tracks))],
            ),
      slivers: [
        if (tracks.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: Icons.library_music_outlined, title: 'This playlist is empty', message: 'Tap ⋮ on any song and choose "Add to playlist".'),
          )
        else
          SliverReorderableList(
            itemCount: tracks.length,
            onReorderItem: (a, b) => lib.reorderPlaylist(p.id, a, b),
            itemBuilder: (_, i) => Material(
              key: ValueKey('pl-${tracks[i].id}'),
              color: Colors.transparent,
              child: TrackTile(
                track: tracks[i],
                inPlaylist: p,
                onTap: () => player.playTracks(tracks, start: i, context: p.name),
                trailing: ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.drag_handle_rounded, color: AppColors.muted))),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// Paste a shared message (or just its code) to rebuild a friend's playlist.
Future<void> showImportDialog(BuildContext context) async {
  final controller = TextEditingController();

  Future<void> paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) controller.text = data!.text!;
  }

  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Import playlist', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paste the message a friend shared from Samgeet.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        TextField(controller: controller, maxLines: 4, decoration: const InputDecoration(hintText: 'Paste the message or link here')),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: paste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: const Text('Paste from clipboard')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Import')),
      ],
    ),
  );
  if (text == null || !context.mounted) return;

  var decoded = ShareService.decodePlaylist(text);
  final code = decoded == null ? shortLinkCode(text) : null;
  if (code != null) {
    final link = await resolveShortLink(code);
    if (!context.mounted) return;
    if (link is SharedPlaylist) decoded = (name: link.name, ids: link.ids);
  }
  if (decoded == null) {
    toast(context, 'That doesn\'t look like a Samgeet playlist');
    return;
  }
  await importPlaylistIds(context, decoded.name, decoded.ids);
}

/// Looks up [ids] and saves them as a new playlist called [name] (also used by tapped share links).
Future<void> importPlaylistIds(BuildContext context, String name, List<String> ids) async {
  final lib = context.read<LibraryStore>();
  final api = context.read<SaavnApi>();
  if (!await allowPlaylistSize(context, ids.length)) return;
  if (!context.mounted) return;
  toast(context, 'Importing ${ids.length} songs…');
  try {
    final tracks = await api.details(ids);
    if (tracks.isEmpty) throw ApiException('No songs could be found');
    final byId = {for (final t in tracks) t.id: t};
    final ordered = [for (final id in ids) ?byId[id]];
    final p = lib.createPlaylist(name, tracks: ordered);
    if (context.mounted) toast(context, 'Imported "${p.name}" (${ordered.length} songs)');
  } catch (e) {
    if (context.mounted) toast(context, 'Import failed: $e');
  }
}
