import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/library_store.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/profile_avatar.dart';
import '../mood_theme.dart';
import '../../app_info.dart';
import 'about_screen.dart';
import 'sign_in_screen.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final topArtists = lib.taste.topArtists(n: 5);
    final topLangs = lib.taste.topLanguages();
    final decade = lib.taste.topDecade();

    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
          child: Text(t.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        section('Account'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassBox(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: lib.signedIn
                ? Row(children: [
                    Pressable(
                      onTap: () => pushPage(context, const SignInScreen()),
                      child: Stack(clipBehavior: Clip.none, children: [
                        ProfileAvatar(initials: lib.profile!.initials, avatar: lib.profile!.avatar, size: 54),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(shape: BoxShape.circle, color: moodPalette(context).accent, border: Border.all(color: AppColors.bg, width: 2)),
                            child: const Icon(Icons.edit_rounded, size: 11, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(lib.profile!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(lib.profile!.email.isEmpty ? 'Playlists unlocked' : lib.profile!.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                      ]),
                    ),
                    TextButton(onPressed: () => pushPage(context, const SignInScreen()), child: const Text('Edit')),
                    TextButton(
                      onPressed: () {
                        lib.signOut();
                        toast(context, 'Signed out');
                      },
                      child: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('You\'re browsing as a guest', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('Sign in to share playlists and keep more than ${LibraryStore.guestPlaylistLimit} songs in a playlist.', style: const TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 14),
                    GradientButton(label: 'Sign in', icon: Icons.login_rounded, compact: true, onTap: () => pushPage(context, const SignInScreen())),
                  ]),
          ),
        ),
        section('Accent style'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final e in MoodPalette.accents.entries)
              Expanded(
                child: _AccentSwatch(
                  palette: e.value,
                  selected: lib.signedIn ? lib.accent == e.key : e.key == 'ember',
                  locked: !lib.signedIn && e.key != 'ember',
                  onTap: () async {
                    if (!lib.signedIn) {
                      await requireSignIn(context, reason: 'Sign in to choose your colour style and let the app follow the mood of your music.');
                      return;
                    }
                    lib.setAccent(e.key);
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(lib.signedIn ? 'Songs with a clear mood (romantic, sad, party…) recolour the app while they play.' : 'Sign in to unlock more colour styles, and colours that follow the mood of your music.', style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
        ),
        section('Streaming quality'),
        RadioGroup<AudioQuality>(
          groupValue: lib.quality,
          onChanged: (v) {
            if (v == null) return;
            lib.setQuality(v);
            player.refreshQuality();
            toast(context, 'Applies to upcoming songs');
          },
          child: Column(children: [
            for (final q in AudioQuality.values)
              RadioListTile<AudioQuality>(
                value: q,
                activeColor: AppColors.pink,
                title: Text(q.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(q == AudioQuality.high ? '${q.detail} · best sound, uses more data' : q.detail, style: const TextStyle(color: AppColors.muted)),
              ),
          ]),
        ),
        section('Playback'),
        SwitchListTile(
          value: lib.autoplay,
          activeThumbColor: AppColors.pink,
          title: const Text('Smart radio', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('When your queue ends, keep playing songs that match the mood', style: TextStyle(color: AppColors.muted)),
          onChanged: lib.setAutoplay,
        ),
        section('Home languages'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in Catalog.languageChoices.entries)
              GlassChip(
                label: e.value,
                selected: lib.languages.contains(e.key),
                onTap: () {
                  final next = [...lib.languages];
                  lib.languages.contains(e.key) ? next.remove(e.key) : next.add(e.key);
                  lib.setLanguages(next);
                },
              ),
          ]),
        ),
        section('Your taste'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(20)),
            child: lib.taste.events == 0
                ? const Text('Samgeet learns from what you finish, like and skip — all on this device. Play a few songs and your taste shows up here.', style: TextStyle(color: AppColors.muted, height: 1.5))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _row('Top artists', topArtists.isEmpty ? 'Still learning…' : topArtists.map((a) => a.name).join(', ')),
                    _row('Languages', topLangs.isEmpty ? 'Still learning…' : topLangs.map((l) => Catalog.languageChoices[l] ?? l).join(', ')),
                    _row('Favourite era', decade == null ? 'Still learning…' : '${decade}s'),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Reset taste profile?'),
                              content: const Text('Recommendations will start fresh. Your playlists and liked songs stay.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
                              ],
                            ),
                          );
                          if (ok == true) lib.resetTaste();
                        },
                        child: const Text('Reset', style: TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ]),
          ),
        ),
        section('Data'),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: const Text('Clear listening history'),
          onTap: () {
            lib.clearHistory();
            toast(context, 'History cleared');
          },
        ),
        ListTile(
          leading: const Icon(Icons.search_off_rounded),
          title: const Text('Clear recent searches'),
          onTap: () {
            lib.clearSearches();
            toast(context, 'Searches cleared');
          },
        ),
        section('About'),
        ListTile(
          leading: Image.asset('assets/mark-chrome.webp', height: 40),
          title: const Text('About $kAppName', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Open source · created by $kAuthor', style: TextStyle(color: AppColors.muted)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: () => pushPage(context, const AboutScreen()),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            '$kCopyright · Version $kAppVersion',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

/// A round preview of one accent style; tap to switch the whole app to it.
class _AccentSwatch extends StatelessWidget {
  final MoodPalette palette;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  const _AccentSwatch({required this.palette, required this.selected, required this.onTap, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2 : 1),
            ),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: palette.gradient),
              child: selected ? const Icon(Icons.check_rounded, size: 22) : (locked ? const Icon(Icons.lock_rounded, size: 18, color: Colors.white70) : null),
            ),
          ),
          const SizedBox(height: 6),
          Text(palette.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.muted)),
        ]),
      ),
    );
  }
}
