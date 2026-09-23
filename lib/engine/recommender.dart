import 'dart:math' as math;

import '../data/track.dart';
import 'taste_profile.dart';

/// Where a candidate song came from. Radio is the strongest "same mood" signal.
enum CandidateSource { radio, sameArtist, taste, context }

class Candidate {
  final Track track;
  final CandidateSource source;

  /// 1.0 = top of its source list, 0.0 = bottom.
  final double sourceRank;
  const Candidate(this.track, this.source, this.sourceRank);
}

/// Pure ranking logic (no I/O) so it can be unit-tested.
///
/// The goal: keep the queue in the *same mood* as the song that's playing,
/// tilt it towards what the listener loves, and avoid monotony.
///
///   score = similarity(seed, c)      language, artists, era, album
///         + radio rank               the catalogue's "sounds like" signal
///         + taste affinity           learned from likes / skips / completions
///         + popularity               a gentle prior for well-loved songs
///         - skip penalty
///
/// Picks are then made greedily with a *flow* term (each pick should feel close
/// to the previous one, so the mood drifts gradually) and a *diversity* term
/// (no artist/album streaks).
class Recommender {
  static const double _wSim = 1.0;
  static const double _wRadio = 0.9;
  static const double _wTaste = 0.7;
  static const double _wPop = 0.25;
  static const double _wFlow = 0.45;

  /// 0..1: how alike two songs are.
  static double similarity(Track a, Track b) {
    var s = 0.0;
    if (a.language.isNotEmpty && a.language == b.language) s += 0.35;
    final artistsA = a.artists.map(TasteProfile.artistKey).toSet();
    final shared = b.artists.map(TasteProfile.artistKey).where(artistsA.contains).length;
    if (shared > 0) s += 0.30 + math.min(0.05, 0.025 * (shared - 1));
    if (a.year > 0 && b.year > 0) s += 0.20 * math.exp(-(a.year - b.year).abs() / 8.0);
    if (a.albumId.isNotEmpty && a.albumId == b.albumId) s += 0.10;
    return s.clamp(0.0, 1.0);
  }

  static double popularity(Track t) => (math.log(t.playCount + 1) / math.ln10 / 9).clamp(0.0, 1.0);

  static double baseScore(Track seed, Candidate c, TasteProfile taste, {Set<String> skipped = const {}}) {
    final t = c.track;
    var score = _wSim * similarity(seed, t) +
        _wRadio * (c.source == CandidateSource.radio ? c.sourceRank : c.sourceRank * 0.5) +
        _wTaste * taste.affinity(t) +
        _wPop * popularity(t);
    // Don't wander into another language unless the listener has a taste for it.
    if (seed.language.isNotEmpty && t.language.isNotEmpty && seed.language != t.language) {
      final lang = taste.affinity(t);
      score -= lang > 0.25 ? 0.10 : 0.35;
    }
    if (skipped.contains(t.id)) score -= 1.5;
    return score;
  }

  /// Picks the next [take] songs to play after [seed].
  static List<Track> rank({
    required Track seed,
    required List<Candidate> pool,
    required TasteProfile taste,
    Set<String> exclude = const {},
    Set<String> skipped = const {},
    int take = 12,
    math.Random? rng,
  }) {
    final random = rng ?? math.Random();
    final seen = <String>{seed.id, ...exclude};
    // One version per song: no "(Lofi Flip)" or "(Slowed)" copy of the seed or of each other.
    final titles = <String>{baseTitle(seed.title)};
    final scored = <_Scored>[];
    for (final c in pool) {
      if (!seen.add(c.track.id)) continue;
      final base = baseTitle(c.track.title);
      if (base.isNotEmpty && !titles.add(base)) continue;
      final jitter = (random.nextDouble() - 0.5) * 0.10; // keeps refreshes from feeling identical
      scored.add(_Scored(c.track, baseScore(seed, c, taste, skipped: skipped) + jitter));
    }

    final picks = <Track>[];
    var prev = seed;
    while (picks.length < take && scored.isNotEmpty) {
      _Scored? best;
      var bestValue = double.negativeInfinity;
      for (final s in scored) {
        var v = s.score + _wFlow * similarity(prev, s.track);
        // Diversity: no artist / album streaks.
        final recent = picks.length >= 3 ? picks.sublist(picks.length - 3) : picks;
        final lastThree = [if (picks.length < 3) seed, ...recent];
        for (final r in lastThree) {
          if (_sharesArtist(r, s.track)) v -= 0.32;
        }
        if (prev.albumId.isNotEmpty && prev.albumId == s.track.albumId) v -= 0.12;
        if (v > bestValue) {
          bestValue = v;
          best = s;
        }
      }
      picks.add(best!.track);
      scored.remove(best);
      prev = best.track;
    }
    return picks;
  }

  /// A title without its "(From ...)", "[Remix]" or " - Lofi" decorations.
  static String baseTitle(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[([].*'), '')
      .split(' - ')
      .first
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  static bool _sharesArtist(Track a, Track b) {
    final ka = a.artists.map(TasteProfile.artistKey).toSet();
    return b.artists.any((x) => ka.contains(TasteProfile.artistKey(x)));
  }
}

class _Scored {
  final Track track;
  final double score;
  _Scored(this.track, this.score);
}
