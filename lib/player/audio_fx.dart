import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ready-made sound. [curve] is gains in dB from the lowest band to the
/// highest; phones differ in band count, so it's stretched to fit.
///
/// The listener's own presets ([isMine]) also keep the loudness [boost] they
/// were saved with; the built-in ones leave the boost alone.
class EqPreset {
  final String id;
  final String label;
  final List<double> curve;
  final double? boost;
  const EqPreset(this.id, this.label, this.curve, {this.boost});

  static const minePrefix = 'my:';
  bool get isMine => id.startsWith(minePrefix);

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'curve': curve, 'boost': ?boost};

  static EqPreset? fromJson(Object? j) {
    if (j is! Map) return null;
    final curve = [for (final v in (j['curve'] as List?) ?? const []) if (v is num) v.toDouble()];
    final id = '${j['id'] ?? ''}', label = '${j['label'] ?? ''}'.trim();
    if (!id.startsWith(minePrefix) || label.isEmpty || curve.isEmpty) return null;
    return EqPreset(id, label, curve, boost: (j['boost'] as num?)?.toDouble());
  }

  static const flat = EqPreset('flat', 'Flat', [0, 0, 0, 0, 0]);
  static const all = [
    flat,
    EqPreset('bass', 'Bass boost', [6, 4, 1, 0, 0]),
    EqPreset('party', 'Party', [5, 2, -1, 2, 5]),
    EqPreset('vocal', 'Vocal', [-2, -1, 3, 4, 1]),
    EqPreset('acoustic', 'Acoustic', [3, 1, 1, 2, 3]),
    EqPreset('treble', 'Treble', [0, 0, 0, 3, 6]),
    EqPreset('night', 'Late night', [-1, 1, 2, 1, -2]),
  ];

  /// Gain for band [i] of [n], read off the curve.
  double gainAt(int i, int n) {
    if (n <= 1) return curve.first;
    final x = i / (n - 1) * (curve.length - 1);
    final lo = x.floor(), hi = math.min(lo + 1, curve.length - 1);
    return curve[lo] + (curve[hi] - curve[lo]) * (x - lo);
  }
}

/// The equalizer and loudness boost on the player's output. Android only:
/// it uses the phone's own audio effects, so elsewhere [supported] is false.
///
/// The phone reports its bands only once the player is connected (after the
/// first song loads), so [bands] stays null until then.
class AudioFx extends ChangeNotifier {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  final AndroidEqualizer _eq = AndroidEqualizer();
  final AndroidLoudnessEnhancer _loudness = AndroidLoudnessEnhancer();

  AudioPipeline get pipeline => supported ? AudioPipeline(androidAudioEffects: [_loudness, _eq]) : AudioPipeline();

  bool enabled = false;
  String preset = EqPreset.flat.id; // or 'custom' (tuned by hand, not saved)

  /// Sounds the listener saved under their own names (they sync with the account).
  List<EqPreset> mine = const [];
  static const maxMine = 20;
  static const maxNameLength = 24;

  List<EqPreset> get allPresets => [...EqPreset.all, ...mine];

  /// What the header shows: the preset's name, or "Custom" for unsaved tuning.
  String get presetLabel => allPresets.where((p) => p.id == preset).map((p) => p.label).firstOrNull ?? 'Custom';
  double boost = 0; // dB, 0..maxBoost
  static const maxBoost = 8.0;

  List<AndroidEqualizerBand>? bands;
  double minDb = -15, maxDb = 15;
  List<double> _saved = const [];

  SharedPreferences? _prefs;
  Timer? _saveTimer;

  AudioFx() {
    if (supported) unawaited(_init());
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    await reload();

    final params = await _eq.parameters;
    minDb = params.minDecibels;
    maxDb = params.maxDecibels;
    bands = params.bands;
    await _applyGains();
    notifyListeners();
  }

  /// Re-reads the saved settings (at start, and after a restore replaced them).
  Future<void> reload() async {
    final p = _prefs;
    if (p == null) return; // still starting; _init reads them
    enabled = p.getBool('fx.enabled') ?? false;
    preset = p.getString('fx.preset') ?? EqPreset.flat.id;
    boost = (p.getDouble('fx.boost') ?? 0).clamp(0, maxBoost);
    _saved = [for (final s in p.getStringList('fx.gains') ?? const <String>[]) double.tryParse(s) ?? 0];
    mine = decodeMine(p.getString('fx.mine'));
    if (preset.startsWith(EqPreset.minePrefix) && !mine.any((m) => m.id == preset)) preset = 'custom'; // deleted on another phone
    await _applyEnabled();
    await _loudness.setTargetGain(boost);
    await _applyGains();
    notifyListeners();
  }

  Future<void> _applyGains() async {
    final b = bands;
    if (b == null) return;
    for (var i = 0; i < b.length; i++) {
      final g = _saved.length == b.length ? _saved[i] : _presetGain(i, b.length);
      await b[i].setGain(g.clamp(minDb, maxDb));
    }
  }

  double _presetGain(int i, int n) =>
      allPresets.firstWhere((p) => p.id == preset, orElse: () => EqPreset.flat).gainAt(i, n);

  Future<void> _applyEnabled() async {
    await _eq.setEnabled(enabled);
    await _loudness.setEnabled(enabled && boost > 0);
  }

  Future<void> setEnabled(bool on) async {
    enabled = on;
    notifyListeners();
    _save();
    await _applyEnabled();
  }

  Future<void> applyPreset(EqPreset p) async {
    preset = p.id;
    _saved = const []; // bands that show up later take the preset, not old custom gains
    if (!enabled) enabled = true;
    notifyListeners();
    _save();
    await _applyEnabled();
    final b = bands;
    if (b == null) return;
    for (var i = 0; i < b.length; i++) {
      await b[i].setGain(p.gainAt(i, b.length).clamp(minDb, maxDb));
    }
    notifyListeners();
    if (p.boost != null) await setBoost(p.boost!);
  }

  // ---------- the listener's own presets ----------
  static List<EqPreset> decodeMine(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) ?EqPreset.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  static String encodeMine(List<EqPreset> list) => jsonEncode([for (final m in list) m.toJson()]);

  static String _trimName(String name) {
    final n = name.trim();
    return n.length > maxNameLength ? n.substring(0, maxNameLength).trim() : n;
  }

  /// Is [name] free? [except] lets a preset keep its own name when renamed.
  bool nameFree(String name, {String? except}) {
    final n = _trimName(name).toLowerCase();
    return n.isNotEmpty && !allPresets.any((p) => p.id != except && p.label.toLowerCase() == n);
  }

  bool get canSave => bands != null && mine.length < maxMine;

  List<double> get _currentCurve => [for (final b in bands ?? const <AndroidEqualizerBand>[]) double.parse(b.gain.toStringAsFixed(2))];

  /// Saves the sound as it is now (bands and loudness boost) under [name], and selects it.
  /// Returns null when there's nothing to save yet (no song has played) or no room left.
  Future<EqPreset?> saveMine(String name) async {
    final curve = _currentCurve;
    if (curve.isEmpty || mine.length >= maxMine || !nameFree(name)) return null;
    final p = EqPreset('${EqPreset.minePrefix}${DateTime.now().millisecondsSinceEpoch}', _trimName(name), curve, boost: boost);
    mine = [...mine, p];
    preset = p.id;
    if (!enabled) {
      enabled = true;
      await _applyEnabled();
    }
    await _storeMine();
    return p;
  }

  /// Replaces a saved preset's sound with what is playing now.
  Future<void> updateMine(String id) async {
    final curve = _currentCurve;
    if (curve.isEmpty) return;
    mine = [for (final m in mine) m.id == id ? EqPreset(m.id, m.label, curve, boost: boost) : m];
    preset = id;
    await _storeMine();
  }

  Future<void> renameMine(String id, String name) async {
    if (!nameFree(name, except: id)) return;
    mine = [for (final m in mine) m.id == id ? EqPreset(m.id, _trimName(name), m.curve, boost: m.boost) : m];
    await _storeMine();
  }

  /// Deletes a saved preset. If it was selected, the sound stays as unsaved tuning.
  Future<void> deleteMine(String id) async {
    mine = [for (final m in mine) if (m.id != id) m];
    if (preset == id) preset = 'custom';
    await _storeMine();
  }

  Future<void> _storeMine() async {
    notifyListeners();
    _save();
    await _prefs?.setString('fx.mine', encodeMine(mine));
  }

  Future<void> setBand(int i, double db) async {
    final b = bands;
    if (b == null) return;
    preset = 'custom';
    if (!enabled) {
      enabled = true;
      unawaited(_applyEnabled());
    }
    await b[i].setGain(db.clamp(minDb, maxDb));
    notifyListeners();
    _save();
  }

  Future<void> setBoost(double db) async {
    boost = db.clamp(0, maxBoost);
    if (!enabled && boost > 0) enabled = true;
    notifyListeners();
    _save();
    await _loudness.setTargetGain(boost);
    await _applyEnabled();
  }

  Future<void> reset() async {
    await setBoost(0);
    await applyPreset(EqPreset.flat);
  }

  // Sliders fire on every frame of a drag; write once it settles.
  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      final p = _prefs;
      if (p == null) return;
      p.setBool('fx.enabled', enabled);
      p.setString('fx.preset', preset);
      p.setDouble('fx.boost', boost);
      final b = bands;
      if (b != null) p.setStringList('fx.gains', [for (final band in b) band.gain.toStringAsFixed(2)]);
    });
  }
}
