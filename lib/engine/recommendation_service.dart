import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

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

  static const dailyMixPref = 'dailyMix';
  static const dailyMixSize = 40;

  static String _day(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "Your Daily Mix": built once a day and kept on the phone, so the home page shows it instantly
  /// and it stays the same all day. [force] builds a fresh one now.
  Future<List<Track>> dailyMix({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _day(DateTime.now());
    if (!force) {
      try {
        final saved = jsonDecode(prefs.getString(dailyMixPref) ?? '{}') as Map;
        if (saved['day'] == today) {
          final tracks = [for (final m in (saved['tracks'] as List).whereType<Map>()) Track.fromJson(Map<String, dynamic>.from(m))];
          if (tracks.isNotEmpty) return tracks;
        }
      } catch (_) {}
    }
    final mix = await madeForYou(take: dailyMixSize, rng: force ? _rng : math.Random(today.hashCode));
    if (mix.isNotEmpty) {
      await prefs.setString(dailyMixPref, jsonEncode({'day': today, 'tracks': [for (final t in mix) t.toJson()]}));
    }
    return mix;
  }

  /// "Made for you": a mix built from what the listener loves right now: songs that sound like
  /// their likes and recent plays, their top and followed singers, and the singers they picked at
  /// sign-in, plus a few of their own favourites to come back to. All sources are fetched at once.
  Future<List<Track>> madeForYou({int take = dailyMixSize, math.Random? rng}) async {
    final random = rng ?? _rng;
    final likes = [...library.favorites.take(12)]..shuffle(random);
    final recent = library.history.take(12).toList()..shuffle(random);
    final seeds = <String, Track>{for (final t in [...likes.take(4), ...recent.take(4)]) t.id: t}.values.toList();
    if (seeds.isEmpty) return _fromPreferences(take);
    final seed = seeds.first;
    String lang(Track t) => t.language.isEmpty || t.language == 'unknown' ? 'hindi' : t.language;

    // Two radios from different seed songs, so the mix isn't one long variation on a single song.
    final groupA = seeds.take(3).toList();
    final groupB = seeds.skip(3).take(3).toList();
    final singers = <String>{
      ...library.taste.topArtists(n: 3).map((a) => a.name),
      ...library.followedArtists.take(2).map((a) => a.name),
      ...(library.profile?.artists ?? const <String>[]).take(2),
    }.where((n) => n.isNotEmpty).take(5).toList();

    final results = await Future.wait([
      _safe(() => api.radio(groupA.map((t) => t.id).toList(), language: lang(groupA.first), count: 30)),
      _safe(() => groupB.isEmpty ? Future.value(<Track>[]) : api.radio(groupB.map((t) => t.id).toList(), language: lang(groupB.first), count: 30)),
      for (final name in singers) _safe(() => api.searchSongs(name, n: 15)),
    ]);
    final favourites = library.favorites.toList()..shuffle(random);
    final pool = <Candidate>[
      ..._asCandidates(results[0], CandidateSource.radio),
      ..._asCandidates(results[1], CandidateSource.radio, start: 0.95),
      for (final r in results.skip(2)) ..._asCandidates(r, CandidateSource.taste, start: 0.8),
      // A handful of songs they already love, mixed in among the new ones.
      ..._asCandidates(favourites.take(6).toList(), CandidateSource.taste, start: 0.6),
    ].where((c) => c.track.isPlayable).toList();

    return Recommender.rank(
      seed: seed,
      pool: pool,
      taste: library.taste,
      // Not what they just heard; the seeds themselves may come back later in the mix.
      exclude: {...library.history.take(15).map((t) => t.id)},
      take: take,
      rng: random,
    );
  }

  /// Before there is any listening history, build the mix from the singers the
  /// listener chose when they signed in.
  Future<List<Track>> _fromPreferences(int take) async {
    final prefs = library.profile?.artists ?? const <String>[];
    if (prefs.isEmpty) return const [];
    final picks = ([...prefs]..shuffle(_rng)).take(5).toList();
    final results = await Future.wait(picks.map((a) => _safe(() => api.searchSongs(a, n: 15))));
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
