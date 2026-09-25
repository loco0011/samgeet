import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A ready-made sound. [curve] is gains in dB from the lowest band to the
/// highest; phones differ in band count, so it's stretched to fit.
class EqPreset {
  final String id;
  final String label;
  final List<double> curve;
  const EqPreset(this.id, this.label, this.curve);

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
  String preset = EqPreset.flat.id; // or 'custom'
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
      EqPreset.all.firstWhere((p) => p.id == preset, orElse: () => EqPreset.flat).gainAt(i, n);

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
