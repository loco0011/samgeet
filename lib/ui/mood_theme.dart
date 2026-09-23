import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/track.dart';
import '../engine/mood.dart';
import '../player/player_controller.dart';
import 'theme.dart';

/// Three colours that dress the app. Every palette is kept on the dark side so
/// white text and the aurora backdrop always read well.
class MoodPalette {
  final String label;
  final IconData icon;
  final List<Color> colors; // exactly three

  const MoodPalette(this.label, this.icon, this.colors);

  LinearGradient get gradient => LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors);

  Color get accent => colors[1];

  /// A lighter tint of the accent, for small dots and icons on the dark page.
  Color get light => Color.lerp(colors[1], Colors.white, 0.5)!;

  /// A brighter version of the gradient for text, so it stays crisp on the dark page.
  LinearGradient get textGradient => LinearGradient(colors: [for (final c in colors) Color.lerp(c, Colors.white, 0.32)!]);

  /// Colour at [t] (0..1) along the palette, for rings and progress.
  Color along(double t) => AppColors.along(colors, t);

  // ---- accent styles the listener can choose in Settings ----
  static const ember = MoodPalette('Ember', Icons.local_fire_department_rounded, [Color(0xFF7A1232), Color(0xFFA61F2E), Color(0xFFB5531A)]);
  static const midnight = MoodPalette('Midnight', Icons.nightlight_round, [Color(0xFF1B1A66), Color(0xFF3B2A93), Color(0xFF5B2B7C)]);
  static const emerald = MoodPalette('Emerald', Icons.eco_rounded, [Color(0xFF0A4D4A), Color(0xFF0D7A66), Color(0xFF14603A)]);
  static const bronze = MoodPalette('Bronze', Icons.wb_twilight_rounded, [Color(0xFF5C3A0F), Color(0xFF9A6A1A), Color(0xFF7A4A22)]);
  static const graphite = MoodPalette('Graphite', Icons.contrast_rounded, [Color(0xFF252A36), Color(0xFF3E4658), Color(0xFF1E2330)]);

  static const accents = <String, MoodPalette>{
    'ember': ember,
    'midnight': midnight,
    'emerald': emerald,
    'bronze': bronze,
    'graphite': graphite,
  };

  /// Used when nothing is playing, or the song has no clear mood.
  static const brand = ember;

  static MoodPalette forAccent(String id) => accents[id] ?? ember;

  // ---- mood palettes (also dark) ----
  static const _byMood = <Mood, MoodPalette>{
    Mood.romantic: MoodPalette('Romantic', Icons.favorite_rounded, [Color(0xFF8E1B4C), Color(0xFFB23A48), Color(0xFF7A2E5E)]),
    Mood.sad: MoodPalette('Melancholy', Icons.heart_broken_rounded, [Color(0xFF1F3A8A), Color(0xFF2E2A78), Color(0xFF0F4C5C)]),
    Mood.party: MoodPalette('Party', Icons.celebration_rounded, [Color(0xFF8A1C6B), Color(0xFFB5651D), Color(0xFF0F5C7A)]),
    Mood.chill: MoodPalette('Chill', Icons.spa_rounded, [Color(0xFF0B5A55), Color(0xFF1E4D8C), Color(0xFF3B2F7A)]),
    Mood.devotional: MoodPalette('Devotional', Icons.self_improvement_rounded, [Color(0xFF8A5A12), Color(0xFFA0451C), Color(0xFF7A5B1E)]),
    Mood.nostalgic: MoodPalette('Nostalgic', Icons.hourglass_bottom_rounded, [Color(0xFF7A5230), Color(0xFF6B3A45), Color(0xFF3F3A66)]),
    Mood.focus: MoodPalette('Focus', Icons.psychology_rounded, [Color(0xFF1F3B8A), Color(0xFF0B5C7A), Color(0xFF3B2F7A)]),
  };

  /// Which palette to wear. Guests always get the default look; signing in
  /// unlocks the accent styles and colours that follow the mood of the music.
  static MoodPalette resolve({Mood? mood, required bool signedIn, required String accent}) =>
      signedIn ? of(mood, accent: accent) : ember;

  static MoodPalette of(Mood? m, {String accent = 'ember'}) => m == null ? forAccent(accent) : _byMood[m]!;

  static MoodPalette lerp(MoodPalette a, MoodPalette b, double t) =>
      MoodPalette(t < 0.5 ? a.label : b.label, t < 0.5 ? a.icon : b.icon, [for (var i = 0; i < 3; i++) Color.lerp(a.colors[i], b.colors[i], t)!]);
}

/// The palette for what is playing right now (watches, so widgets repaint on change).
MoodPalette moodPalette(BuildContext context) => context.watch<MoodController>().palette;

class MoodPaletteTween extends Tween<MoodPalette> {
  MoodPaletteTween({super.begin, super.end});

  @override
  MoodPalette lerp(double t) => MoodPalette.lerp(begin ?? end!, end!, t);
}

/// Watches what is playing (and the chosen accent style) and decides the app's palette.
///
/// The colours follow the mood of the *session*, not of each song: see
/// [MoodMomentum] (3 of the last 5 songs, then held for at least 5 minutes).
class MoodController extends ChangeNotifier {
  final PlayerController player;
  final LibraryStore library;
  final MoodMomentum _momentum;

  /// The mood the colours have settled on.
  Mood? get mood => _momentum.current;

  /// The mood of the song playing right now (may differ from [mood]).
  Mood? songMood;

  MoodPalette palette = MoodPalette.brand;
  String? _key;
  String _accent;
  bool _signedIn;
  bool _follow;

  /// True when the app is actually wearing mood colours (signed in, switched on, a mood has settled).
  bool get themed => _signedIn && _follow && mood != null;

  MoodController(this.player, this.library, {MoodMomentum? momentum})
      : _momentum = momentum ?? MoodMomentum(current: Mood.values.where((m) => m.name == library.themeMood).firstOrNull),
        _accent = library.accent,
        _signedIn = library.signedIn,
        _follow = library.moodColors {
    palette = _resolve();
    player.addListener(_update);
    library.addListener(_libraryChanged);
    _update();
  }

  MoodPalette _resolve() => MoodPalette.resolve(mood: _follow ? mood : null, signedIn: _signedIn, accent: _accent);

  void _libraryChanged() {
    if (library.accent == _accent && library.signedIn == _signedIn && library.moodColors == _follow) return;
    _accent = library.accent;
    _signedIn = library.signedIn;
    _follow = library.moodColors;
    _apply();
  }

  void _update() {
    final Track? t = player.current;
    final key = t == null ? null : '${t.id}|${player.sessionContext}';
    if (key == _key) return;
    _key = key;
    if (t == null) return; // stopping keeps the colours the session settled on
    songMood = MoodDetector.detect(t, context: player.sessionContext);
    if (_momentum.played(songMood)) library.rememberThemeMood(mood?.name);
    _apply();
  }

  void _apply() {
    final next = _resolve();
    if (!identical(next, palette)) palette = next;
    notifyListeners(); // 'themed' or the song's mood may have changed even when the colours did not
  }

  @override
  void dispose() {
    player.removeListener(_update);
    library.removeListener(_libraryChanged);
    super.dispose();
  }
}
