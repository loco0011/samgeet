import 'dart:math' as math;

import '../data/track.dart';

/// Things the listener does that tell us how they feel about a song.
enum TasteEvent {
  completed(1.0), // listened to most of it
  partial(0.35), // listened for a while
  skipped(-1.4), // bailed out early
  liked(3.0),
  unliked(-2.5),
  addedToPlaylist(1.8),
  followedArtist(4.0);

  final double weight;
  const TasteEvent(this.weight);
}

class _Weight {
  double value;
  int ts; // epoch ms of last update
  _Weight(this.value, this.ts);
  Map<String, dynamic> toJson() => {'v': value, 't': ts};
  factory _Weight.fromJson(Map<String, dynamic> j) =>
      _Weight((j['v'] as num).toDouble(), (j['t'] as num).toInt());
}

/// What the listener enjoys, learned on-device.
///
/// Every signal decays with a 30-day half-life so the profile follows the
/// listener's changing taste instead of being dominated by ancient history.
class TasteProfile {
  static const double halfLifeDays = 30;
  static const double _maxWeight = 40;

  final Map<String, _Weight> _artists = {};
  final Map<String, _Weight> _languages = {};
  final Map<String, _Weight> _decades = {};
  final Map<String, String> _artistNames = {};
  int events = 0;

  TasteProfile();

  static String artistKey(ArtistRef a) => a.id.isNotEmpty ? a.id : a.name.toLowerCase();

  double _now(int nowMs, _Weight w) {
    final days = (nowMs - w.ts) / Duration.millisecondsPerDay;
    return w.value * math.pow(0.5, days / halfLifeDays);
  }

  void _bump(Map<String, _Weight> m, String key, double delta, int nowMs) {
    if (key.isEmpty) return;
    final w = m[key];
    final current = w == null ? 0.0 : _now(nowMs, w);
    m[key] = _Weight((current + delta).clamp(-12.0, _maxWeight), nowMs);
  }

  void record(Track t, TasteEvent e, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final w = e.weight;
    final n = t.artists.length;
    for (final a in t.artists) {
      // Credit is split when a song has many artists.
      _bump(_artists, artistKey(a), w / math.sqrt(math.max(1, n)), now);
      _artistNames[artistKey(a)] = a.name;
    }
    if (t.language.isNotEmpty) _bump(_languages, t.language, w * 0.6, now);
    if (t.decade > 0) _bump(_decades, '${t.decade}', w * 0.5, now);
    events++;
    if (_artists.length > 400) _prune(_artists, now);
  }

  void _prune(Map<String, _Weight> m, int now) {
    final keys = m.keys.toList()..sort((a, b) => _now(now, m[a]!).abs().compareTo(_now(now, m[b]!).abs()));
    for (final k in keys.take(m.length - 300)) {
      m.remove(k);
      _artistNames.remove(k);
    }
  }

  double _get(Map<String, _Weight> m, String key, int now) {
    final w = m[key];
    return w == null ? 0 : _now(now, w);
  }

  /// How much the listener is likely to enjoy [t], from -1 (dislikes) to +1 (loves).
  double affinity(Track t, {int? nowMs}) {
    if (events == 0) return 0;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    var artist = 0.0;
    for (final a in t.artists) {
      final v = _get(_artists, artistKey(a), now);
      if (v.abs() > artist.abs()) artist = v;
    }
    final lang = _get(_languages, t.language, now);
    final decade = t.decade > 0 ? _get(_decades, '${t.decade}', now) : 0.0;
    return 0.55 * _tanh(artist / 6) + 0.30 * _tanh(lang / 15) + 0.15 * _tanh(decade / 10);
  }

  static double _tanh(double x) {
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  /// The artists the listener currently loves most.
  List<ArtistRef> topArtists({int n = 5, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final entries = _artists.entries.map((e) => MapEntry(e.key, _now(now, e.value))).where((e) => e.value > 1.0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries
        .take(n)
        .map((e) => ArtistRef(id: RegExp(r'^\d+$').hasMatch(e.key) ? e.key : '', name: _artistNames[e.key] ?? e.key))
        .toList();
  }

  List<String> topLanguages({int n = 3, int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final entries = _languages.entries.map((e) => MapEntry(e.key, _now(now, e.value))).where((e) => e.value > 0.8).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).map((e) => e.key).toList();
  }

  /// Favourite decade, e.g. 1990.
  int? topDecade({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    MapEntry<String, double>? best;
    for (final e in _decades.entries) {
      final v = _now(now, e.value);
      if (v > 0.8 && (best == null || v > best.value)) best = MapEntry(e.key, v);
    }
    return best == null ? null : int.tryParse(best.key);
  }

  Map<String, dynamic> toJson() => {
        'artists': _artists.map((k, v) => MapEntry(k, v.toJson())),
        'languages': _languages.map((k, v) => MapEntry(k, v.toJson())),
        'decades': _decades.map((k, v) => MapEntry(k, v.toJson())),
        'names': _artistNames,
        'events': events,
      };

  factory TasteProfile.fromJson(Map<String, dynamic> j) {
    final p = TasteProfile();
    void load(String key, Map<String, _Weight> into) {
      final m = j[key];
      if (m is Map) {
        m.forEach((k, v) => into['$k'] = _Weight.fromJson(Map<String, dynamic>.from(v)));
      }
    }

    load('artists', p._artists);
    load('languages', p._languages);
    load('decades', p._decades);
    final names = j['names'];
    if (names is Map) names.forEach((k, v) => p._artistNames['$k'] = '$v');
    p.events = (j['events'] as num?)?.toInt() ?? 0;
    return p;
  }
}
