import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_info.dart';
import '../../data/library_store.dart';
import '../../data/sync_service.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../screens/sign_in_screen.dart';
import '../theme.dart';
import 'common.dart';

/// Once per app version, after it opens: asks a guest to sign in, or someone who signed in before
/// passwords existed to add one, so their library is backed up. Nothing for a listener who already syncs.
Future<void> maybeShowSignInNudge(BuildContext context) async {
  final lib = context.read<LibraryStore>();
  if (context.read<SyncService>().loggedIn) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(SyncService.nudgePref) == kVersionName) return;
    await prefs.setString(SyncService.nudgePref, kVersionName);
  } catch (_) {
    return;
  }
  if (!context.mounted) return;
  final go = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SignInNudgeSheet(name: lib.profile?.name),
  );
  if (go == true && context.mounted) pushPage(context, const SignInScreen());
}

class SignInNudgeSheet extends StatelessWidget {
  /// Set when they're signed in already (without a password): the sheet then asks for a password.
  final String? name;
  const SignInNudgeSheet({super.key, this.name});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final legacy = name != null;
    final first = name?.trim().split(RegExp(r'\s+')).first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: mood.light.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: -8)],
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 22),
          _Badge(mood: mood),
          const SizedBox(height: 20),
          Text(
            legacy ? 'One tiny step, $first' : 'Keep your music safe',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: kDisplay, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ).animate().fadeIn(delay: 150.ms, duration: 400.ms).slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 8),
          Text(
            legacy
                ? 'Add a password and your playlists, likes and history are backed up to your account.'
                : 'Sign in with your email and a password and your playlists, likes and history go wherever you go.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.45, fontSize: 14),
          ).animate().fadeIn(delay: 250.ms, duration: 400.ms),
          const SizedBox(height: 20),
          for (final (i, p) in _perks.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: mood.accent.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                  child: Icon(p.$1, size: 19, color: mood.light),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(p.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
              ]),
            ).animate().fadeIn(delay: (320 + 80 * i).ms, duration: 350.ms).slideX(begin: 0.08, end: 0, curve: Curves.easeOutCubic),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: Center(
              child: GradientButton(
                label: legacy ? 'Add a password' : 'Sign in',
                icon: legacy ? Icons.lock_rounded : Icons.login_rounded,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ).animate().fadeIn(delay: 560.ms, duration: 350.ms).scaleXY(begin: 0.94, end: 1, curve: Curves.easeOutBack),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Maybe later', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  static const _perks = [
    (Icons.devices_rounded, 'The same library on every phone'),
    (Icons.restore_rounded, 'Everything comes back after a reinstall'),
    (Icons.lock_rounded, 'Your password never leaves your phone'),
  ];
}

/// A glowing cloud with little notes floating around it.
class _Badge extends StatelessWidget {
  final MoodPalette mood;
  const _Badge({required this.mood});

  @override
  Widget build(BuildContext context) {
    Widget note(double dx, double dy, double size, int delayMs) => Positioned(
          left: 60 + dx,
          top: 60 + dy,
          child: Icon(Icons.music_note_rounded, size: size, color: mood.light)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn(delay: delayMs.ms, duration: 500.ms)
              .moveY(begin: 4, end: -6, duration: 1600.ms, curve: Curves.easeInOut),
        );
    return SizedBox(
      width: 140,
      height: 120,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: mood.gradient,
            boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.55), blurRadius: 36, spreadRadius: 2)],
          ),
          child: const Icon(Icons.cloud_done_rounded, size: 46, color: Colors.white),
        )
            // A slow breathing pulse, inside a one-time pop-in.
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(begin: 1, end: 1.05, duration: 1800.ms, curve: Curves.easeInOut)
            .animate()
            .scaleXY(begin: 0.6, end: 1, duration: 500.ms, curve: Curves.easeOutBack),
        note(-58, -46, 18, 300),
        note(40, -54, 14, 450),
        note(52, 10, 16, 600),
      ]),
    );
  }
}
