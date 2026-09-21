import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/device_snapshot.dart';
import '../../data/library_store.dart';
import '../../data/profile.dart';
import '../nav.dart';
import '../mood_theme.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/profile_avatar.dart';

/// Palette colours can be deep; lift them so icons stay readable on the dark page.
Color _lift(Color c) => Color.lerp(c, Colors.white, 0.55)!;

const _moodChoices = <String, String>{
  'romantic': 'Romantic',
  'sad': 'Heartbreak',
  'party': 'Party',
  'chill': 'Chill',
  'workout': 'Workout',
  'focus': 'Focus',
  'devotional': 'Devotional',
  'nostalgia': 'Nostalgia',
  'lofi': 'Lo-fi',
  'rain': 'Rainy day',
};

/// Sign in (or edit your profile) and tell Samgeet what you like.
/// Pops with `true` once a profile has been saved.
class SignInScreen extends StatefulWidget {
  /// Why the user was sent here, e.g. "Sign in to share playlists".
  final String? reason;
  const SignInScreen({super.key, this.reason});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  final Set<String> _languages = {};
  final Set<String> _moods = {};
  final Set<String> _artists = {};
  String? _emailError;
  String _avatar = ''; // id from kAvatarIcons; empty = initials
  bool _share = false; // opt-in: device details + approximate location
  bool _saving = false;

  bool get _editing => context.read<LibraryStore>().signedIn;

  @override
  void initState() {
    super.initState();
    final p = context.read<LibraryStore>().profile;
    _name = TextEditingController(text: p?.name ?? '')..addListener(() => setState(() {}));
    _email = TextEditingController(text: p?.email ?? '');
    _languages.addAll(p?.languages ?? const ['hindi', 'bengali']);
    _moods.addAll(p?.moods ?? const []);
    _artists.addAll(p?.artists ?? const []);
    _share = p?.shareDeviceInfo ?? false;
    _avatar = p?.avatar ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _email.text.trim().isNotEmpty;

  void _toggle(Set<String> set, String v) => setState(() => set.contains(v) ? set.remove(v) : set.add(v));

  Future<void> _submit() async {
    if (_saving) return;
    // Lower-cased so the same address always identifies the same person.
    final email = _email.text.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailError = 'That email doesn\'t look right');
      return;
    }
    final lib = context.read<LibraryStore>();
    final existing = lib.profile;
    final wasEditing = existing != null;
    // Only look at the device (and ask for the location permission) if they opted in.
    // Turning it off drops whatever was stored.
    DeviceSnapshot? device;
    if (_share) {
      setState(() => _saving = true);
      device = await DeviceSnapshot.capture();
      if (!mounted) return;
    }
    final profile = Profile(
      name: _name.text.trim(),
      email: email,
      languages: _languages.toList(),
      moods: _moods.toList(),
      artists: _artists.toList(),
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      avatar: _avatar,
      shareDeviceInfo: _share,
      device: device,
    );
    lib.signIn(profile);
    Navigator.of(context).pop(true);
    toast(context, wasEditing ? 'Profile saved' : 'Welcome to Samgeet, ${profile.name}!');
  }

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final editing = _editing;
    final singers = <String>{for (final g in Catalog.artistGroups) ...g.names}.toList();
    final initials = Profile(name: _name.text, createdAt: 0).initials;

    Widget section(String title, String subtitle, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: kDisplay, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 12),
            child,
          ]),
        );

    Widget chips(Map<String, String> choices, Set<String> selected) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in choices.entries) GlassChip(label: e.value, selected: selected.contains(e.key), onTap: () => _toggle(selected, e.key)),
        ]);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(22, 0, 22, 24), children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Image.asset('assets/mark-chrome.webp', height: 84),
              ),
              const SizedBox(height: 18),
              Text(editing ? 'Your profile' : 'Sign in to Samgeet',
                  style: const TextStyle(fontFamily: kDisplay, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 6),
              Text(
                editing ? 'Update what you like and your suggestions will follow.' : 'It takes a few seconds and unlocks the good stuff.',
                style: const TextStyle(color: AppColors.muted, height: 1.4),
              ),
              if (widget.reason != null) ...[
                const SizedBox(height: 16),
                GlassBox(
                  radius: 18,
                  tint: mood.accent,
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.lock_open_rounded, size: 20, color: _lift(mood.colors[0])),
                    const SizedBox(width: 12),
                    Expanded(child: Text(widget.reason!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35))),
                  ]),
                ),
              ],
              const SizedBox(height: 22),
              const GlassBox(
                radius: 20,
                padding: EdgeInsets.all(16),
                child: Column(children: [
                  _Perk(Icons.palette_rounded, 'Colours that follow the mood of your music'),
                  SizedBox(height: 12),
                  _Perk(Icons.ios_share_rounded, 'Share your playlists with friends'),
                  SizedBox(height: 12),
                  _Perk(Icons.library_music_rounded, 'Playlists with unlimited songs (guests: ${LibraryStore.guestPlaylistLimit})'),
                  SizedBox(height: 12),
                  _Perk(Icons.auto_awesome_rounded, 'Suggestions tuned to you from day one'),
                ]),
              ),
              section(
                'Profile picture',
                'Pick an icon, or keep your initials',
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  ProfileAvatar(initials: initials, avatar: _avatar, size: 68),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      _AvatarChoice(selected: _avatar.isEmpty, onTap: () => setState(() => _avatar = ''), child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                      for (final e in kAvatarIcons.entries)
                        _AvatarChoice(selected: _avatar == e.key, onTap: () => setState(() => _avatar = e.key), child: Icon(e.value, size: 20)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.person_outline_rounded)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() => _emailError = null),
                decoration: InputDecoration(
                  labelText: 'Email',
                  helperText: 'Required. It identifies your account.',
                  errorText: _emailError,
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              section('Languages you love', 'Sets what shows on your home page', chips(Catalog.languageChoices, _languages)),
              section('Moods you like', 'We\'ll put these first', chips(_moodChoices, _moods)),
              section(
                'Favourite singers',
                'Pick a few — your daily mix starts here',
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final n in singers) GlassChip(label: n, selected: _artists.contains(n), onTap: () => _toggle(_artists, n)),
                ]),
              ),
              const SizedBox(height: 22),
              GlassBox(
                radius: 18,
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(children: [
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Share device details', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      SizedBox(height: 3),
                      Text(
                        'Your device model and approximate location (city level, asks permission) are saved with your profile to help improve Samgeet. Off by default, and you can turn it off any time.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                      ),
                    ]),
                  ),
                  Switch(value: _share, onChanged: (v) => setState(() => _share = v)),
                ]),
              ),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.phone_android_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your profile is saved on this phone. There is no password and no cloud sync yet.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                  ),
                ),
              ]),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _valid ? 1 : 0.4,
              child: SizedBox(
                width: double.infinity,
                child: Center(child: GradientButton(label: editing ? 'Save changes' : 'Continue', icon: Icons.arrow_forward_rounded, onTap: _valid && !_saving ? _submit : null)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One small round option in the profile-picture picker.
class _AvatarChoice extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const _AvatarChoice({required this.selected, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? mood.accent.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: selected ? mood.accent : Colors.white24, width: selected ? 2 : 1),
        ),
        child: IconTheme(data: IconThemeData(color: selected ? Colors.white : AppColors.muted), child: DefaultTextStyle.merge(style: TextStyle(color: selected ? Colors.white : AppColors.muted), child: child)),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Perk(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: _lift(moodPalette(context).colors[0])),
      const SizedBox(width: 14),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
    ]);
  }
}
