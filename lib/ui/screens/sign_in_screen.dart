import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/device_snapshot.dart';
import '../../data/library_store.dart';
import '../../data/profile.dart';
import '../../data/sync_service.dart';
import '../nav.dart';
import '../mood_theme.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/account_widgets.dart';

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
  final _pass = TextEditingController();
  String? _emailError;
  String? _nameError;
  String? _passError;
  String _avatar = ''; // see Profile.avatar
  String? _newPhoto; // a photo copied in during this visit; removed again unless saved
  bool _saved = false;
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
    _pass.dispose();
    if (!_saved) _deleteFile(_newPhoto);
    super.dispose();
  }

  void _deleteFile(String? path) {
    if (path != null) File(path).delete().catchError((_) => File(path));
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (picked == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final dest = '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(picked.path).copy(dest);
      _deleteFile(_newPhoto); // an earlier pick from this visit
      _newPhoto = dest;
      if (mounted) setState(() => _avatar = '${Profile.photoPrefix}$dest');
    } catch (_) {
      if (mounted) toast(context, 'Couldn\'t load that photo');
    }
  }

  // New here: email + password (the name is asked for if it's a new account).
  // Editing: name + email; the password is only there while this phone isn't syncing yet.
  bool get _valid => _email.text.trim().isNotEmpty && (_editing ? _name.text.trim().isNotEmpty : _pass.text.isNotEmpty);

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
    final sync = context.read<SyncService>();
    final existing = lib.profile;
    final wasEditing = existing != null;

    // With a password: sign in to the account if there is one (the library comes back), else make one.
    AccountCheck? account;
    if (!sync.loggedIn && (_pass.text.isNotEmpty || !wasEditing)) {
      if (_pass.text.length < SyncService.minPasswordLength) {
        setState(() => _passError = 'At least ${SyncService.minPasswordLength} characters');
        return;
      }
      setState(() => _saving = true);
      account = await sync.check(email, _pass.text);
      if (!mounted) return;
      final problem = switch (account.state) {
        AccountState.wrongPassword => 'Wrong password for this email',
        AccountState.offline => 'No internet. Connect to sign in.',
        AccountState.slowDown => 'Too many tries. Wait 10 minutes and try again.',
        AccountState.broken => 'Something went wrong. Try again in a bit.',
        _ => null,
      };
      if (problem != null) {
        setState(() {
          _saving = false;
          _passError = problem;
        });
        return;
      }
      if (account.state == AccountState.existing && !wasEditing) {
        await sync.join(account); // brings the library, profile included
        if (!mounted) return;
        if (lib.signedIn) {
          Navigator.of(context).pop(true);
          toast(context, 'Welcome back, ${lib.profile!.name}!');
          return;
        }
      }
      if (_name.text.trim().isEmpty) {
        setState(() {
          _saving = false;
          _nameError = 'New here? Add your name to create your account.';
        });
        return;
      }
    }

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
    _saved = true;
    // Tidy up photos that are no longer the picture: the old saved one, or an unused pick.
    final oldPhoto = existing?.photoPath;
    if (oldPhoto != null && oldPhoto != profile.photoPath) _deleteFile(oldPhoto);
    if (_newPhoto != null && _newPhoto != profile.photoPath) _deleteFile(_newPhoto);
    if (account != null) {
      await lib.flush(); // so the new account starts with this profile
      unawaited(sync.join(account));
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    toast(context, wasEditing ? (account != null ? 'Profile saved. Your library is backed up now.' : 'Profile saved') : 'Welcome to Samgeet, ${profile.name}!');
  }

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final editing = _editing;
    final initials = Profile(name: _name.text, createdAt: 0).initials;
    final hasPhoto = _avatar.startsWith(Profile.photoPrefix);

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
                  SizedBox(height: 12),
                  _Perk(Icons.cloud_done_rounded, 'The same library on every phone you sign in on'),
                ]),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                onChanged: (_) => setState(() => _emailError = null),
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _emailError,
                  prefixIcon: const Icon(Icons.mail_outline_rounded),
                ),
              ),
              if (!context.read<SyncService>().loggedIn) ...[
                const SizedBox(height: 12),
                PasswordField(
                  controller: _pass,
                  label: editing ? 'Password (optional)' : 'Password',
                  helper: editing
                      ? 'Add one to back up your library and get it on other phones.'
                      : 'Been here before? Your playlists and favourites come back. New? This creates your account.',
                  error: _passError,
                  onChanged: (_) => setState(() => _passError = null),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _nameError = null),
                decoration: InputDecoration(
                  labelText: editing ? 'Your name' : 'Your name (if you\'re new)',
                  errorText: _nameError,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                ),
              ),
              section(
                'Profile picture',
                'Upload a photo, or pick an icon or emoji',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    ProfileAvatar(initials: initials, avatar: _avatar, size: 68),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        GlassChip(label: hasPhoto ? 'Change photo' : 'Upload photo', icon: Icons.photo_library_rounded, selected: hasPhoto, onTap: _pickPhoto),
                        if (hasPhoto) GlassChip(label: 'Remove', icon: Icons.delete_outline_rounded, selected: false, onTap: () => setState(() => _avatar = '')),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _AvatarChoice(selected: _avatar.isEmpty, onTap: () => setState(() => _avatar = ''), child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
                    for (final e in kAvatarIcons.entries)
                      _AvatarChoice(selected: _avatar == e.key, onTap: () => setState(() => _avatar = e.key), child: Icon(e.value, size: 20)),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in kAvatarEmojis)
                      _AvatarChoice(selected: _avatar == '${Profile.emojiPrefix}$e', onTap: () => setState(() => _avatar = '${Profile.emojiPrefix}$e'), child: Text(e, style: const TextStyle(fontSize: 20))),
                  ]),
                ]),
              ),
              section('Languages you love', 'Sets what shows on your home page', chips(Catalog.languageChoices, _languages)),
              section('Moods you like', 'We\'ll put these first', chips(_moodChoices, _moods)),
              section(
                'Favourite singers',
                'Pick a few — your daily mix starts here',
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final g in Catalog.artistGroups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Row(children: [
                        Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (g.names.any(_artists.contains)) ...[
                          const SizedBox(width: 8),
                          Text('${g.names.where(_artists.contains).length} picked', style: TextStyle(color: mood.light, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ]),
                    ),
                    // One swipeable row per group keeps the long list compact.
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: g.names.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Center(child: GlassChip(dense: true, label: g.names[i], selected: _artists.contains(g.names[i]), onTap: () => _toggle(_artists, g.names[i]))),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
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
                    'Your profile, playlists, favourites, history and settings are saved on this phone and synced to your account on Samgeet\'s server. Sign in with the same email and password on any phone to get them. Your password never leaves the phone and can\'t be reset, so remember it. Uploaded photos stay on this phone.',
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
