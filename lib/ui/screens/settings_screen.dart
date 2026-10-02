import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/admin_service.dart';
import '../../data/sync_service.dart';
import '../../data/catalog.dart';
import '../../data/download_service.dart';
import '../../data/library_store.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/account_widgets.dart';
import '../widgets/download_widgets.dart';
import '../widgets/player_style_picker.dart';
import '../widgets/taste_pickers.dart';
import '../mood_theme.dart';
import '../../app_info.dart';
import 'about_screen.dart';
import 'admin_screen.dart';
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
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Sign out?'),
                            content: Text(
                              context.read<SyncService>().loggedIn
                                  ? 'This phone stops syncing. Your library stays in your account: sign in again with your email and password to get it back.'
                                  : 'Your playlists and favourites stay on this phone, but they aren\'t backed up: you haven\'t set a password yet.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                            ],
                          ),
                        );
                        if (ok != true || !context.mounted) return;
                        await lib.signOut();
                        if (!context.mounted) return;
                        toast(context, 'Signed out');
                      },
                      child: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('You\'re browsing as a guest', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text('Sign in to like, download and share songs, pick your player look, and keep your library on every phone.', style: const TextStyle(color: AppColors.muted, height: 1.4)),
                    const SizedBox(height: 14),
                    GradientButton(label: 'Sign in', icon: Icons.login_rounded, compact: true, onTap: () => pushPage(context, const SignInScreen())),
                  ]),
          ),
        ),
        if (lib.signedIn)
          ListenableBuilder(
            listenable: context.read<SyncService>(),
            builder: (context, _) {
              final s = context.read<SyncService>();
              final ok = s.status == SyncStatus.synced || s.status == SyncStatus.syncing;
              return Padding(
                padding: const EdgeInsets.fromLTRB(26, 10, 20, 0),
                child: Row(children: [
                  Icon(ok ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, size: 16, color: ok ? moodPalette(context).light : AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(syncStatusText(s), style: const TextStyle(color: AppColors.muted, fontSize: 12.5))),
                ]),
              );
            },
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
        if (lib.signedIn)
          SwitchListTile(
            value: lib.moodColors,
            activeThumbColor: AppColors.pink,
            title: const Text('Colours follow the music', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              lib.moodColors
                  ? 'When 3 of your last 5 songs share a mood (romantic, sad, party…), the app takes on its colours. They stay for at least 5 minutes.'
                  : 'The app keeps the accent style you picked above.',
              style: const TextStyle(color: AppColors.muted),
            ),
            onChanged: lib.setMoodColors,
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text('Sign in to unlock more colour styles, and colours that follow the mood of your music.', style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
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
        section('Downloads'),
        Builder(builder: (context) {
          final dl = context.watch<DownloadService>();
          return Column(children: [
            RadioGroup<AudioQuality>(
              groupValue: dl.quality,
              onChanged: (v) {
                if (v != null) dl.setQuality(v);
              },
              child: Column(children: [
                for (final q in AudioQuality.values)
                  RadioListTile<AudioQuality>(
                    value: q,
                    activeColor: AppColors.pink,
                    title: Text(q.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      switch (q) {
                        AudioQuality.high => '${q.detail} · best sound, about 9 MB for a 4-minute song',
                        AudioQuality.medium => '${q.detail} · about 5 MB for a 4-minute song',
                        AudioQuality.low => '${q.detail} · about 3 MB for a 4-minute song',
                      },
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: Text('${plural(dl.count, 'song')} saved · ${DownloadService.size(dl.totalBytes)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Kept privately inside Samgeet on this phone. They play without internet.', style: TextStyle(color: AppColors.muted)),
              trailing: dl.count == 0 ? null : TextButton(onPressed: () => confirmRemoveAllDownloads(context), child: const Text('Remove all', style: TextStyle(color: Colors.redAccent))),
            ),
          ]);
        }),
        section('Playback'),
        ListTile(
          leading: SizedBox(
            width: 34,
            height: 44,
            child: ClipRRect(borderRadius: BorderRadius.circular(7), child: StylePreview(style: lib.hasAccount ? lib.playerStyle : PlayerStyle.disc, accent: moodPalette(context).accent)),
          ),
          title: const Text('Player look', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            lib.hasAccount ? '${lib.playerStyle.label} · ${lib.playerStyle.description}' : 'Sign in to choose Disc, Cover, Immersive or Minimal',
            style: const TextStyle(color: AppColors.muted),
          ),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: () => showPlayerStylePicker(context),
        ),
        SwitchListTile(
          value: lib.autoplay,
          activeThumbColor: AppColors.pink,
          title: const Text('Smart radio', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('When your queue ends, keep playing songs that match the mood', style: TextStyle(color: AppColors.muted)),
          onChanged: lib.setAutoplay,
        ),
        section('Your choices'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassBox(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _ChoiceHeading('Languages you love', 'Sets what shows on your home page'),
              ChoiceChips(
                choices: Catalog.languageChoices,
                selected: lib.languages.toSet(),
                onToggle: (k) {
                  final next = [...lib.languages];
                  lib.languages.contains(k) ? next.remove(k) : next.add(k);
                  lib.setLanguages(next);
                },
              ),
              if (lib.signedIn) ...[
                const _ChoiceHeading('Moods you like', 'These come first in your suggestions'),
                ChoiceChips(
                  choices: kMoodChoices,
                  selected: lib.profile!.moods.toSet(),
                  onToggle: (k) {
                    final next = [...lib.profile!.moods];
                    next.contains(k) ? next.remove(k) : next.add(k);
                    lib.updateChoices(moods: next);
                  },
                ),
                _ChoiceHeading('Favourite singers', lib.profile!.artists.isEmpty ? 'Pick a few and your Daily Mix starts with them' : '${plural(lib.profile!.artists.length, 'singer')} picked'),
                SingerPicker(
                  selected: lib.profile!.artists.toSet(),
                  onToggle: (name) {
                    final next = [...lib.profile!.artists];
                    next.contains(name) ? next.remove(name) : next.add(name);
                    lib.updateChoices(artists: next);
                  },
                ),
              ] else ...[
                const SizedBox(height: 14),
                Pressable(
                  onTap: () => requireSignIn(context, reason: 'Sign in to save your moods and favourite singers.'),
                  child: const Row(children: [
                    Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.muted),
                    SizedBox(width: 8),
                    Expanded(child: Text('Sign in to pick moods and favourite singers', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600))),
                    Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
              ],
            ]),
          ),
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
        if (lib.hasAccount && lib.sync != null)
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
            title: const Text('Delete my account', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700)),
            subtitle: const Text('Removes your account, synced library and listening data from Samgeet\'s server', style: TextStyle(color: AppColors.muted)),
            onTap: () => _deleteAccount(context, lib),
          ),
        section('About'),
        ListTile(
          leading: Image.asset('assets/mark-chrome.webp', height: 40),
          title: const Text('About $kAppName', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Open source · created by $kAuthor', style: TextStyle(color: AppColors.muted)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: () => pushPage(context, const AboutScreen()),
        ),
        if (context.read<AdminService>().signedIn)
          ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Send a message to listeners', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Admin', style: TextStyle(color: AppColors.muted)),
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            onTap: () => pushPage(context, const AdminScreen()),
          ),
        const _VersionLine(),
      ]),
    );
  }

  Future<void> _deleteAccount(BuildContext context, LibraryStore lib) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'Your account, the synced copy of your library and everything Samgeet recorded about your listening are removed from the server. '
            'Playlists and likes stay on this phone, and you are signed out. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await lib.sync!.deleteAccount();
    if (!context.mounted) return;
    if (!done) {
      toast(context, 'Couldn\'t reach Samgeet\'s server. Try again when you\'re online.');
      return;
    }
    await lib.signOut();
    if (context.mounted) toast(context, 'Account deleted');
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

/// The copyright and version line. Tapping it 7 times opens the admin tools (they still need the
/// admin password).
class _VersionLine extends StatefulWidget {
  const _VersionLine();

  @override
  State<_VersionLine> createState() => _VersionLineState();
}

class _VersionLineState extends State<_VersionLine> {
  int _taps = 0;
  DateTime _last = DateTime(0);

  void _tap() {
    final now = DateTime.now();
    _taps = now.difference(_last) < const Duration(seconds: 1) ? _taps + 1 : 1;
    _last = now;
    if (_taps >= 7) {
      _taps = 0;
      pushPage(context, const AdminScreen());
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text('$kCopyright · Version $kAppVersion', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      );
}

/// A small heading inside the Your choices card.
class _ChoiceHeading extends StatelessWidget {
  final String title;
  final String subtitle;
  const _ChoiceHeading(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
        ]),
      );
}
