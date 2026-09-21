import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/catalog.dart';
import '../data/library_store.dart';
import '../data/share_service.dart';
import '../data/saavn_api.dart';
import '../data/track.dart';
import '../player/player_controller.dart';
import 'screens/artist_screen.dart';
import 'screens/category_screen.dart';
import 'screens/collection_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme.dart';

/// Fade + slight rise transition for pushed pages.
///
/// Pages have transparent backgrounds (the aurora is painted behind the
/// navigator), so two pages fading at once would show through each other. The
/// page underneath therefore fades out first ([secondary] is driven by the page
/// pushed on top of it) and the new page fades in after, with no overlap.
///
/// [coverBelow] is for routes pushed on the root navigator, where what is
/// underneath (the whole app shell) cannot fade itself out: a solid backdrop
/// fades in first so it does not show through the incoming page.
Route<T> fadeRoute<T>(Widget page, {bool coverBelow = false}) => PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, secondary, child) {
        final enter = CurvedAnimation(parent: anim, curve: const Interval(0.4, 1, curve: Curves.easeOutCubic));
        final leave = CurvedAnimation(parent: secondary, curve: const Interval(0, 0.4, curve: Curves.easeIn));
        final view = FadeTransition(
          opacity: ReverseAnimation(leave),
          child: FadeTransition(
            opacity: enter,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(enter),
              child: child,
            ),
          ),
        );
        if (!coverBelow) return view;
        final cover = CurvedAnimation(parent: anim, curve: const Interval(0, 0.4, curve: Curves.easeOut));
        return Stack(fit: StackFit.expand, children: [
          FadeTransition(opacity: cover, child: const ColoredBox(color: AppColors.bg)),
          view,
        ]);
      },
    );

Future<T?> pushPage<T>(BuildContext context, Widget page) => Navigator.of(context).push<T>(fadeRoute(page));

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

void openCategory(BuildContext context, Category c) => pushPage(context, CategoryScreen(category: c));

void openArtist(BuildContext context, ArtistRef a) => pushPage(context, ArtistScreen(artist: a));

void openAlbum(BuildContext context, String albumId, String title) {
  if (albumId.isEmpty) return;
  pushPage(context, CollectionScreen.album(id: albumId, title: title));
}

/// Opens whatever a browse card points to: plays a song, or opens an album / playlist / artist.
Future<void> openCard(BuildContext context, MediaCard c) async {
  switch (c.kind) {
    case CardKind.song:
      final api = context.read<SaavnApi>();
      final player = context.read<PlayerController>();
      try {
        final t = (await api.details([c.id])).firstOrNull;
        if (t != null) await player.playSingle(t);
      } catch (_) {
        if (context.mounted) toast(context, 'Couldn\'t load that song');
      }
    case CardKind.album:
      pushPage(context, CollectionScreen.album(id: c.id, title: c.title, image: c.image, subtitle: c.subtitle));
    case CardKind.playlist:
    case CardKind.chart:
      pushPage(context, CollectionScreen.playlist(id: c.id, title: c.title, image: c.image, subtitle: c.subtitle));
    case CardKind.artist:
      pushPage(context, ArtistScreen(artist: ArtistRef(id: c.id, name: c.title, image: c.image)));
    case CardKind.radio:
      toast(context, 'Radio stations aren\'t supported yet');
  }
}

/// Makes sure the listener has a profile, asking them to create one if not.
/// Returns true when they are signed in (already, or just now).
Future<bool> requireSignIn(BuildContext context, {required String reason}) async {
  if (context.read<LibraryStore>().signedIn) return true;
  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(fadeRoute(SignInScreen(reason: reason), coverBelow: true));
  return ok == true;
}

/// Guests can keep up to [LibraryStore.guestPlaylistLimit] songs in a playlist.
/// Returns true if a playlist of [count] songs is allowed (asking to sign in if not).
Future<bool> allowPlaylistSize(BuildContext context, int count) {
  if (context.read<LibraryStore>().canHold(count)) return Future.value(true);
  return requireSignIn(
    context,
    reason: 'Guests can keep up to ${LibraryStore.guestPlaylistLimit} songs in a playlist. Sign in to add more.',
  );
}

/// Sharing a playlist needs a profile.
Future<void> sharePlaylistGated(BuildContext context, String name, List<Track> tracks) async {
  if (!await requireSignIn(context, reason: 'Sign in to share playlists with your friends.')) return;
  await ShareService.sharePlaylist(name, tracks);
}

/// "1 song" / "2 songs".
String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
