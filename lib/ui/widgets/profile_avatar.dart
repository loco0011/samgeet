import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/profile.dart';
import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';

/// Icons a listener can pick as their profile picture.
const kAvatarIcons = <String, IconData>{
  'headphones': Icons.headphones_rounded,
  'guitar': Icons.music_note_rounded,
  'mic': Icons.mic_rounded,
  'piano': Icons.piano_rounded,
  'album': Icons.album_rounded,
  'star': Icons.star_rounded,
  'heart': Icons.favorite_rounded,
  'bolt': Icons.bolt_rounded,
  'moon': Icons.nightlight_round,
  'sun': Icons.wb_sunny_rounded,
  'flower': Icons.local_florist_rounded,
  'fire': Icons.local_fire_department_rounded,
};

/// Emoji a listener can pick as their profile picture.
const kAvatarEmojis = ['🎧', '🎵', '🎤', '🎸', '🥁', '🎷', '😎', '🥰', '🔥', '🌙', '🌸', '🦋', '🐯', '🦄', '👑', '🚀'];

/// The round profile picture: a glowing gradient ring around a photo, an emoji, an icon or the initials.
class ProfileAvatar extends StatelessWidget {
  final String initials;
  final String avatar;
  final double size;
  const ProfileAvatar({super.key, required this.initials, this.avatar = '', this.size = 54});

  @override
  Widget build(BuildContext context) {
    final palette = moodPalette(context);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: palette.gradient, boxShadow: [BoxShadow(color: palette.accent.withValues(alpha: 0.45), blurRadius: size / 3.4)]),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        child: _content(palette),
      ),
    );
  }

  Widget _initials(MoodPalette palette) =>
      GradientText(initials, gradient: palette.textGradient, style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w800, letterSpacing: -0.5));

  Widget _content(MoodPalette palette) {
    if (avatar.startsWith(Profile.photoPrefix)) {
      return Image.file(
        File(avatar.substring(Profile.photoPrefix.length)),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _initials(palette), // e.g. the file was cleared
      );
    }
    if (avatar.startsWith(Profile.emojiPrefix)) {
      return Text(avatar.substring(Profile.emojiPrefix.length), style: TextStyle(fontSize: size * 0.48));
    }
    final icon = kAvatarIcons[avatar];
    if (icon != null) {
      return ShaderMask(
        shaderCallback: (r) => palette.textGradient.createShader(r),
        blendMode: BlendMode.srcIn,
        child: Icon(icon, size: size * 0.5, color: Colors.white),
      );
    }
    return _initials(palette);
  }
}
