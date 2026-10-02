import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../mood_theme.dart';
import '../theme.dart';
import 'common.dart';

/// The look of a [FancyDialog]'s header.
enum FancyTone { info, celebrate, warning }

/// Samgeet's popup: a glowing header (icon or picture), a title, a body and one big button.
/// Used for app updates and for messages sent from the admin panel.
class FancyDialog extends StatelessWidget {
  final IconData icon;
  final String? imageUrl;
  final String? badge; // small pill above the title, e.g. "1.3.3 → 1.4.0"
  final String title;
  final Widget body;
  final String primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback onPrimary;
  final List<Widget> secondary; // text buttons under the big one
  final FancyTone tone;
  final VoidCallback? onClose; // null: no close button (required updates)

  const FancyDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.imageUrl,
    this.badge,
    this.primaryIcon,
    this.secondary = const [],
    this.tone = FancyTone.info,
    this.onClose,
  });

  List<Color> _colors(MoodPalette mood) => switch (tone) {
        FancyTone.info => mood.colors,
        FancyTone.celebrate => const [Color(0xFFB5531A), Color(0xFFD0284F), Color(0xFF7A1232)],
        FancyTone.warning => const [Color(0xFF8A5A12), Color(0xFFE0A33F), Color(0xFF7A1232)],
      };

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final colors = _colors(mood);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: size.height * 0.86),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _Header(icon: icon, imageUrl: imageUrl, colors: colors, onClose: onClose),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (badge != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: colors[1].withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                        child: Text(badge!, style: TextStyle(color: Color.lerp(colors[1], Colors.white, 0.45), fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(title, style: const TextStyle(fontFamily: kDisplay, fontSize: 22, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
                    const SizedBox(height: 10),
                    DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFFD9D9E6), height: 1.45, fontSize: 14), child: body),
                  ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Column(children: [
                  SizedBox(
                    width: double.infinity,
                    child: Center(child: GradientButton(label: primaryLabel, icon: primaryIcon, onTap: onPrimary)),
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(alignment: WrapAlignment.center, spacing: 4, children: secondary),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String? imageUrl;
  final List<Color> colors;
  final VoidCallback? onClose;
  const _Header({required this.icon, required this.imageUrl, required this.colors, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return SizedBox(
      height: hasImage ? 190 : 150,
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors))),
        if (hasImage)
          Artwork(imageUrl!, radius: 0, cacheSize: 800)
        else ...[
          // Soft glowing blobs behind the icon.
          Positioned(left: -40, top: -50, child: _Blob(color: Colors.white.withValues(alpha: 0.16), size: 170)),
          Positioned(right: -30, bottom: -60, child: _Blob(color: colors[0].withValues(alpha: 0.7), size: 180)),
          Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Icon(icon, size: 38, color: Colors.white),
            ),
          ),
        ],
        // Fades into the card below.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 40,
          child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, AppColors.surface]))),
        ),
        if (onClose != null)
          Positioned(
            right: 10,
            top: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.28),
              shape: const CircleBorder(),
              child: IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose, tooltip: 'Close'),
            ),
          ),
      ]),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      );
}

/// Shows [dialog] with Samgeet's popup animation (a quick rise and fade).
Future<T?> showFancy<T>(BuildContext context, Widget dialog, {bool dismissible = true}) => showGeneralDialog<T>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: dismissible,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => PopScope(canPop: dismissible, child: dialog),
      transitionBuilder: (_, anim, _, child) {
        final a = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(a), child: child),
        );
      },
    );
