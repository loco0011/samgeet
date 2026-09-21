import 'dart:math' as math;

import '../data/library_store.dart';
import '../data/saavn_api.dart';
import '../data/track.dart';
import 'recommender.dart';

/// Gathers candidate songs from the network and hands them to [Recommender].
class RecommendationService {
  final SaavnApi api;
  final LibraryStore library;
  final math.Random _rng = math.Random();

  RecommendationService(this.api, this.library);

  Future<List<Track>> _safe(Future<List<Track>> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return const [];
    }
  }

  List<Candidate> _asCandidates(List<Track> tracks, CandidateSource source, {double start = 1.0}) {
    final n = math.max(1, tracks.length);
    return [
      for (var i = 0; i < tracks.length; i++) Candidate(tracks[i], source, start * (1 - i / n)),
    ];
  }

  /// The next batch of songs that fit the mood of [seed].
  ///
  /// [previous] keeps the mood steady (radio is seeded with two songs, so one
  /// odd track can't yank the queue somewhere else).
  /// [contextQuery] is the category the listener started from (e.g. "romantic").
  Future<List<Track>> nextBatch({
    required Track seed,
    Track? previous,
    Set<String> exclude = const {},
    Set<String> skipped = const {},
    String? contextQuery,
    int take = 12,
  }) async {
    final language = seed.language.isEmpty || seed.language == 'unknown' ? 'hindi' : seed.language;
    final seeds = [seed.id, if (previous != null && previous.id != seed.id) previous.id];

    // Sometimes slip in something from the listener's favourite artists, so the
    // queue feels personal without becoming a loop.
    ArtistRef? tasteArtist;
    final top = library.taste.topArtists(n: 4).where((a) => a.name != seed.primaryArtist).toList();
    if (top.isNotEmpty && _rng.nextDouble() < 0.55) tasteArtist = top[_rng.nextInt(top.length)];

    final results = await Future.wait([
      _safe(() => api.radio(seeds, language: language, count: 25)),
      _safe(() => seed.primaryArtist.isEmpty ? Future.value(<Track>[]) : api.searchSongs(seed.primaryArtist, n: 12)),
      _safe(() => tasteArtist == null ? Future.value(<Track>[]) : api.searchSongs(tasteArtist.name, n: 10)),
      _safe(() => contextQuery == null ? Future.value(<Track>[]) : api.searchSongs(contextQuery, n: 15)),
    ]);

    final pool = <Candidate>[
      ..._asCandidates(results[0], CandidateSource.radio),
      ..._asCandidates(results[1], CandidateSource.sameArtist, start: 0.8),
      ..._asCandidates(results[2], CandidateSource.taste, start: 0.7),
      ..._asCandidates(results[3], CandidateSource.context, start: 0.7),
    ].where((c) => c.track.isPlayable).toList();

    return Recommender.rank(
      seed: seed,
      pool: pool,
      taste: library.taste,
      exclude: {...exclude, ...library.history.take(25).map((t) => t.id)},
      skipped: skipped,
      take: take,
      rng: _rng,
    );
  }

  /// "Made for you": a mix built from what the listener loves right now.
  /// Returns an empty list until there's enough listening history.
  Future<List<Track>> madeForYou({int take = 25}) async {
    final seeds = <Track>[
      ...library.favorites.take(3),
      ...library.history.take(3),
    ];
    final unique = <String, Track>{for (final t in seeds) t.id: t};
    if (unique.isEmpty) return _fromPreferences(take);
    final list = unique.values.toList()..shuffle(_rng);
    final seed = list.first;
    final language = seed.language.isEmpty ? 'hindi' : seed.language;

    final results = await Future.wait([
      _safe(() => api.radio(list.take(3).map((t) => t.id).toList(), language: language, count: 30)),
      ...library.taste.topArtists(n: 2).map((a) => _safe(() => api.searchSongs(a.name, n: 12))),
    ]);
    final pool = <Candidate>[
      ..._asCandidates(results[0], CandidateSource.radio),
      for (final r in results.skip(1)) ..._asCandidates(r, CandidateSource.taste, start: 0.8),
    ].where((c) => c.track.isPlayable).toList();

    return Recommender.rank(
      seed: seed,
      pool: pool,
      taste: library.taste,
      exclude: {for (final t in list) t.id},
      take: take,
      rng: _rng,
    );
  }

  /// Before there is any listening history, build the mix from the singers the
  /// listener chose when they signed in.
  Future<List<Track>> _fromPreferences(int take) async {
    final prefs = library.profile?.artists ?? const <String>[];
    if (prefs.isEmpty) return const [];
    final picks = ([...prefs]..shuffle(_rng)).take(3).toList();
    final results = await Future.wait(picks.map((a) => _safe(() => api.searchSongs(a, n: 12))));
    final pool = <Candidate>[
      for (final r in results) ..._asCandidates(r, CandidateSource.taste, start: 0.9),
    ].where((c) => c.track.isPlayable).toList();
    if (pool.isEmpty) return const [];
    return Recommender.rank(seed: pool.first.track, pool: pool, taste: library.taste, take: take, rng: _rng);
  }

  /// A mix seeded by one song (used for "Start radio" and "Because you played…").
  Future<List<Track>> similarTo(Track seed, {int take = 25}) =>
      nextBatch(seed: seed, take: take, exclude: {seed.id});
}
