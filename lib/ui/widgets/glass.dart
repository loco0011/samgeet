import 'dart:ui';

import 'package:flutter/material.dart';

import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';

/// A frosted-glass panel with a soft light-catching edge.
class GlassBox extends StatelessWidget {
  final Widget? child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  /// Real background blur. Costly, so only used for the dock and mini-player.
  final bool blur;
  final double? width;
  final double? height;

  const GlassBox({
    super.key,
    this.child,
    this.radius = 20,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.blur = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final outer = BorderRadius.circular(radius);
    final inner = BorderRadius.circular(radius - 1);
    final framed = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: outer,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.13)],
        ),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: inner,
          color: tint == null ? Colors.white.withValues(alpha: 0.055) : tint!.withValues(alpha: 0.20),
        ),
        child: child,
      ),
    );
    if (!blur) return framed;
    return ClipRRect(borderRadius: outer, child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: framed));
  }
}

/// A pill-shaped filter. Selected chips glow with the aurora gradient.
class GlassChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  /// Smaller padding and text, for long lists of chips.
  final bool dense;
  const GlassChip({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(1.2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: selected
              ? mood.gradient
              : LinearGradient(colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.05)]),
          boxShadow: selected ? [BoxShadow(color: mood.accent.withValues(alpha: 0.4), blurRadius: 14)] : null,
        ),
        child: Container(
          padding: dense ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: selected ? AppColors.bg.withValues(alpha: 0.55) : AppColors.bg.withValues(alpha: 0.35),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: dense ? 12.5 : 13.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.muted),
            ),
          ]),
        ),
      ),
    );
  }
}
