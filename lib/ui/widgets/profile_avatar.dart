import 'package:flutter/material.dart';

import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';

/// Icons a listener can pick as their profile picture. An empty id means "use my initials".
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

/// The round profile picture: a glowing gradient ring around either the chosen icon or the initials.
class ProfileAvatar extends StatelessWidget {
  final String initials;
  final String avatar;
  final double size;
  const ProfileAvatar({super.key, required this.initials, this.avatar = '', this.size = 54});

  @override
  Widget build(BuildContext context) {
    final palette = moodPalette(context);
    final icon = kAvatarIcons[avatar];
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: palette.gradient, boxShadow: [BoxShadow(color: palette.accent.withValues(alpha: 0.45), blurRadius: size / 3.4)]),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
        alignment: Alignment.center,
        child: icon != null
            ? ShaderMask(
                shaderCallback: (r) => palette.textGradient.createShader(r),
                blendMode: BlendMode.srcIn,
                child: Icon(icon, size: size * 0.5, color: Colors.white),
              )
            : GradientText(initials, gradient: palette.textGradient, style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      ),
    );
  }
}
