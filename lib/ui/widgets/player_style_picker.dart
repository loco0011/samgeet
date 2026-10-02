import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';

/// Lets a signed-in listener choose how the full-screen player looks. [welcome] is the version
/// shown right after signing in.
Future<void> showPlayerStylePicker(BuildContext context, {bool welcome = false}) async {
  if (!await requireSignIn(context, reason: 'Sign in to choose how your player looks.')) return;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _StylePicker(welcome: welcome),
  );
}

class _StylePicker extends StatelessWidget {
  final bool welcome;
  const _StylePicker({required this.welcome});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final mood = moodPalette(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Text(welcome ? 'Make the player yours' : 'Player look',
              style: const TextStyle(fontFamily: kDisplay, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(
            welcome ? 'You\'re signed in, so you can pick how songs look while they play. Change it any time in Settings.' : 'Pick how songs look while they play.',
            style: const TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.74,
            children: [
              for (final s in PlayerStyle.values)
                _StyleCard(
                  style: s,
                  selected: lib.playerStyle == s,
                  accent: mood.accent,
                  onTap: () {
                    lib.setPlayerStyle(s);
                    Navigator.of(context).pop();
                    toast(context, '${s.label} look on. Open the player to see it.');
                  },
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final PlayerStyle style;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  const _StyleCard({required this.style, required this.selected, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : AppColors.outline, width: selected ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(14), child: StylePreview(style: style, accent: accent))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(style.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (selected) Icon(Icons.check_circle_rounded, size: 18, color: accent),
            if (style == PlayerStyle.disc && !selected) const Text('Original', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
          const SizedBox(height: 2),
          Text(style.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3)),
        ]),
      ),
    );
  }
}

/// A tiny drawing of each player look.
class StylePreview extends StatelessWidget {
  final PlayerStyle style;
  final Color accent;
  const StylePreview({super.key, required this.style, required this.accent});

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, {double h = 5, double a = 0.7}) =>
        Container(width: w, height: h, decoration: BoxDecoration(color: Colors.white.withValues(alpha: a), borderRadius: BorderRadius.circular(3)));
    Widget controls() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          Icon(Icons.skip_previous_rounded, size: 14, color: Colors.white.withValues(alpha: 0.8)),
          Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: accent), child: const Icon(Icons.play_arrow_rounded, size: 14)),
          Icon(Icons.skip_next_rounded, size: 14, color: Colors.white.withValues(alpha: 0.8)),
        ]);
    final art = DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [accent, Color.lerp(accent, AppColors.ember3, 0.6)!], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: const Center(child: Icon(Icons.music_note_rounded, size: 18, color: Colors.white70)),
    );
    final bg = BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [accent.withValues(alpha: 0.55), AppColors.bg]));

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return switch (style) {
        PlayerStyle.disc => Container(
            decoration: bg,
            padding: const EdgeInsets.all(10),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              Container(
                width: w * 0.55,
                height: w * 0.55,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: accent, width: 2)),
                child: ClipOval(child: art),
              ),
              bar(w * 0.5),
              controls(),
            ]),
          ),
        PlayerStyle.cover => Container(
            decoration: bg,
            padding: const EdgeInsets.all(10),
            child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: w * 0.62, height: w * 0.62, child: art)),
              Align(alignment: Alignment.centerLeft, child: bar(w * 0.45)),
              Stack(children: [bar(w, h: 3, a: 0.25), bar(w * 0.4, h: 3, a: 1)]),
              controls(),
            ]),
          ),
        PlayerStyle.immersive => Stack(fit: StackFit.expand, children: [
            Opacity(opacity: 0.85, child: art),
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [bar(w * 0.5), const SizedBox(height: 6), controls()]),
              ),
            ),
          ]),
        PlayerStyle.minimal => Container(
            color: AppColors.bg,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ClipOval(child: SizedBox(width: 26, height: 26, child: art)),
              bar(w * 0.8, h: 10, a: 0.95),
              bar(w * 0.5, h: 6, a: 0.5),
              Stack(children: [bar(w, h: 2, a: 0.2), bar(w * 0.6, h: 2, a: 1)]),
              controls(),
            ]),
          ),
      };
    });
  }
}
