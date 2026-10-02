import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'fuzzy.dart';
import 'track.dart';

class HomeData {
  final List<MediaCard> trending;
  final List<MediaCard> newAlbums;
  final List<MediaCard> playlists;
  final List<MediaCard> charts;
  final List<MediaCard> artists;
  const HomeData({
    this.trending = const [],
    this.newAlbums = const [],
    this.playlists = const [],
    this.charts = const [],
    this.artists = const [],
  });
}

class ArtistPage {
  final ArtistRef artist;
  final String bio;
  final String followers;
  final List<Track> topSongs;
  final List<MediaCard> albums;
  final List<ArtistRef> similar;
  const ArtistPage({
    required this.artist,
    this.bio = '',
    this.followers = '',
    this.topSongs = const [],
    this.albums = const [],
    this.similar = const [],
  });
}

class SongSearch {
  final List<Track> songs;

  /// The spelling that actually found the best match, when it differs from
  /// what was typed (used to fill the other result tabs).
  final String? correctedQuery;
  const SongSearch(this.songs, {this.correctedQuery});
}

class SearchSuggestions {
  final List<String> queries;
  const SearchSuggestions(this.queries);
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Talks to the free streaming catalogue directly from the device.
/// Everything is cached in memory for a short while so navigation feels instant.
class SaavnApi {
  static const _host = 'www.jiosaavn.com';
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

  final http.Client _client;
  final Map<String, _Cached> _cache = {};
  // Requests on their way, so the same call made twice at once (typing, then pressing search)
  // goes over the network once.
  final Map<String, Future<dynamic>> _inflight = {};
  SaavnApi({http.Client? client}) : _client = client ?? http.Client();

  /// Searches ignore case and extra spaces, so "Arijit  Singh" and "arijit singh" share a cache entry.
  static String normQuery(String q) => q.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  Future<dynamic> _get(
    String call,
    Map<String, String> params, {
    Duration ttl = const Duration(minutes: 15),
    String? cookie,
    bool force = false,
  }) {
    final key = '$call|${jsonEncode(params)}|${cookie ?? ''}';
    final hit = _cache[key];
    if (!force && hit != null && DateTime.now().isBefore(hit.expires)) return Future.value(hit.value);
    final running = _inflight[key];
    if (running != null && !force) return running;
    // (A block body: returning the removed future here would make it wait for itself.)
    final f = _fetch(call, params, key, ttl, cookie).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = f;
    return f;
  }

  Future<dynamic> _fetch(String call, Map<String, String> params, String key, Duration ttl, String? cookie) async {
    final q = <String, String>{
      '__call': call,
      '_format': 'json',
      '_marker': '0',
      'ctx': 'web6dot0',
      'api_version': '4',
      ...params,
    };
    final uri = Uri.https(_host, '/api.php', q);

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _client.get(uri, headers: {
          'User-Agent': _ua,
          'Accept': 'application/json',
          'Cookie': ?cookie,
        }).timeout(const Duration(seconds: 15));
        if (res.statusCode != 200) throw ApiException('Server returned ${res.statusCode}');
        final body = jsonDecode(utf8.decode(res.bodyBytes));
        _cache[key] = _Cached(body, DateTime.now().add(ttl));
        if (_cache.length > 300) _cache.remove(_cache.keys.first);
        return body;
      } catch (e) {
        lastError = e;
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
    throw ApiException(
        lastError is TimeoutException ? 'Connection timed out' : 'Could not reach the music server');
  }

  // ---- parsing helpers ----
  List<Track> _tracks(dynamic list) {
    if (list is! List) return const [];
    final out = <Track>[];
    for (final e in list) {
      if (e is Map) {
        final t = Track.fromJson(Map<String, dynamic>.from(e));
        if (t.id.isNotEmpty && t.title.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  List<MediaCard> _cards(dynamic list) {
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => MediaCard.fromJson(Map<String, dynamic>.from(m)))
        .whereType<MediaCard>()
        .toList();
  }

  /// The launch data lists recommended artists as "artist radio" stations
  /// (same id as the artist), so turn them into plain artist cards.
  List<MediaCard> _artistCards(dynamic list) {
    if (list is! List) return const [];
    return [
      for (final m in list.whereType<Map>())
        if ('${m['id']}'.isNotEmpty && '${m['title'] ?? ''}'.isNotEmpty)
          MediaCard(kind: CardKind.artist, id: '${m['id']}', title: '${m['title']}', image: '${m['image'] ?? ''}'),
    ];
  }

  // ---- search ----
  Future<List<Track>> searchSongs(String query, {int n = 30, int page = 1}) async {
    final j = await _get('search.getResults', {'q': normQuery(query), 'p': '$page', 'n': '$n'});
    return _tracks(j['results']);
  }

  /// Song search that forgives typos, partial names and lyric lines.
  ///
  /// The catalogue search copes with small misspellings but returns nothing
  /// when one word of a longer query is wrong ("blinding lite weeknd"), and it
  /// doesn't search lyrics. So this also:
  ///  * puts the autocomplete's own song picks first (it matches lyric lines:
  ///    "mujhko itna bataaye koi" -> Kesariya);
  ///  * when the direct results are thin or don't look like what was typed,
  ///    tries the autocomplete's guesses and the query with each word left out;
  /// then ranks everything by how closely it matches the query.
  ///
  /// [quick] is for results while typing: the extra spellings are only tried when the direct
  /// search found nothing, so each pause in typing costs two or three requests, not eight.
  Future<SongSearch> findSongs(String query, {int n = 30, bool quick = false}) async {
    final q = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    final direct = await Future.wait<dynamic>([
      searchSongs(q, n: n),
      _autocomplete(q).catchError((_) => null),
    ]);
    final primary = direct[0] as List<Track>;
    final ac = direct[1];
    final acIds = _acSongIds(ac).take(4).toList();
    final guesses = [for (final e in _acEntries(ac, const ['topquery', 'songs'])) cleanText('${e['title'] ?? ''}')];

    double best(List<Track> l) => l.take(5).fold(0.0, (m, t) => math.max(m, Fuzzy.songScore(q, t)));
    final strong = quick ? primary.isNotEmpty : primary.length >= 8 && best(primary) >= 0.8;

    final lower = q.toLowerCase();
    final alternatives = strong
        ? const <String>[]
        : <String>{
            ...guesses.where((g) => g.isNotEmpty && g.toLowerCase() != lower).take(2),
            ...Fuzzy.dropOneWord(q),
          }.take(6).toList();
    final more = await Future.wait<List<Track>>([
      acIds.isEmpty ? Future.value(const <Track>[]) : details(acIds).catchError((_) => <Track>[]),
      for (final a in alternatives) searchSongs(a, n: 15).catchError((_) => <Track>[]),
    ]);
    final byId = {for (final t in more[0]) t.id: t};
    final picks = [for (final id in acIds) ?byId[id]];

    final scored = <String, ({Track track, double score, String from})>{};
    void put(Track t, double s, String from) {
      final prev = scored[t.id];
      if (prev == null || s > prev.score) scored[t.id] = (track: t, score: s, from: from);
    }

    // Direct results keep a head start; alternatives must actually look like the query.
    void add(List<Track> list, String from, double head) {
      for (var i = 0; i < list.length; i++) {
        final t = list[i];
        final match = Fuzzy.songScore(q, t);
        if (from != q && match < 0.4) continue;
        put(t, match + head * (1 - i / math.max(1, list.length)), from);
      }
    }

    add(primary, q, 0.25);
    for (var i = 0; i < alternatives.length; i++) {
      add(more[i + 1], alternatives[i], 0.12);
    }
    // The autocomplete's picks may share no words with the query (a lyric
    // line), so they're trusted as they are, the first one most.
    for (var i = 0; i < picks.length; i++) {
      put(picks[i], math.max(Fuzzy.songScore(q, picks[i]), 0.9) + 0.35 * (1 - i / picks.length), q);
    }

    final ranked = scored.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    final top = ranked.isEmpty ? null : ranked.first;
    return SongSearch(
      ranked.take(n).map((e) => e.track).toList(),
      correctedQuery: top != null && top.from != q ? top.from : null,
    );
  }

  Future<List<MediaCard>> searchPlaylists(String query, {int n = 12}) async {
    final j = await _get('search.getPlaylistResults', {'q': normQuery(query), 'p': '1', 'n': '$n'});
    return _cards(j['results']).map((c) => c).toList();
  }

  Future<List<MediaCard>> searchAlbums(String query, {int n = 12}) async {
    final j = await _get('search.getAlbumResults', {'q': normQuery(query), 'p': '1', 'n': '$n'});
    return _cards(j['results']);
  }

  Future<List<ArtistRef>> searchArtists(String query, {int n = 12}) async {
    final j = await _get('search.getArtistResults', {'q': normQuery(query), 'p': '1', 'n': '$n'});
    final list = j['results'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => ArtistRef.fromJson({
              'id': m['id'],
              'name': m['name'] ?? m['title'],
              'image': m['image'],
            }))
        .where((a) => a.name.isNotEmpty)
        .toList();
  }

  Future<dynamic> _autocomplete(String query) =>
      _get('autocomplete.get', {'query': normQuery(query)}, ttl: const Duration(minutes: 5));

  List<Map> _acEntries(dynamic j, List<String> keys) => [
        for (final k in keys)
          if (j is Map && j[k] is Map && j[k]['data'] is List) ...(j[k]['data'] as List).whereType<Map>(),
      ];

  /// Ids of the songs the autocomplete matched, best first. The autocomplete
  /// also matches lyric lines, so this is how "a line from the song" is found.
  List<String> _acSongIds(dynamic j) {
    final ids = <String>[];
    for (final e in _acEntries(j, const ['topquery', 'songs'])) {
      final id = '${e['id'] ?? ''}';
      if (e['type'] == 'song' && id.isNotEmpty && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  Future<List<String>> suggestions(String query) async {
    if (query.trim().length < 2) return const [];
    final j = await _autocomplete(query);
    final out = <String>[];
    for (final e in _acEntries(j, const ['topquery', 'songs', 'artists', 'albums'])) {
      final t = cleanText('${e['title'] ?? ''}');
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return out.take(8).toList();
  }

  // ---- details ----
  Future<Collection> playlist(String id, {int n = 100}) async {
    final j = await _get('playlist.getDetails', {'listid': id, 'n': '$n', 'p': '1'});
    return Collection(
      id: '${j['id']}',
      title: '${j['title'] ?? ''}'.trim(),
      subtitle: '${j['subtitle'] ?? ''}'.trim(),
      image: '${j['image'] ?? ''}',
      permaUrl: '${j['perma_url'] ?? ''}',
      tracks: _tracks(j['list']),
    );
  }

  Future<Collection> album(String id) async {
    final j = await _get('content.getAlbumDetails', {'albumid': id});
    return Collection(
      id: '${j['id']}',
      title: '${j['title'] ?? ''}'.trim(),
      subtitle: '${j['subtitle'] ?? j['header_desc'] ?? ''}'.trim(),
      image: '${j['image'] ?? ''}',
      permaUrl: '${j['perma_url'] ?? ''}',
      tracks: _tracks(j['list']),
    );
  }

  Future<ArtistPage> artist(String id) async {
    final j = await _get('artist.getArtistPageDetails', {'artistId': id, 'n_song': '25', 'n_album': '15'});
    final songs = j['topSongs'] is List ? j['topSongs'] : (j['topSongs']?['songs']);
    final similar = <ArtistRef>[];
    if (j['similarArtists'] is List) {
      for (final m in (j['similarArtists'] as List).whereType<Map>()) {
        final a = ArtistRef.fromJson({'id': m['id'], 'name': m['name'] ?? m['title'], 'image': m['image']});
        if (a.id.isNotEmpty && a.name.isNotEmpty) similar.add(a);
      }
    }
    final followers = int.tryParse('${j['follower_count'] ?? ''}') ?? 0;
    return ArtistPage(
      artist: ArtistRef(id: '${j['artistId'] ?? id}', name: '${j['name'] ?? ''}', image: '${j['image'] ?? ''}'),
      bio: _bioText(j['bio']),
      followers: followers > 0 ? _compact(followers) : '',
      topSongs: _tracks(songs),
      albums: _cards(j['topAlbums']),
      similar: similar,
    );
  }

  String _bioText(dynamic bio) {
    if (bio is String && bio.trim().startsWith('[')) {
      try {
        final l = jsonDecode(bio) as List;
        return l.map((e) => '${e['text'] ?? ''}').join('\n\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      } catch (_) {}
    }
    return bio is String ? bio.replaceAll(RegExp(r'<[^>]*>'), '').trim() : '';
  }

  static String _compact(int n) {
    if (n >= 10000000) return '${(n / 10000000).toStringAsFixed(1)}Cr';
    if (n >= 100000) return '${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  /// Fetches fresh details (including stream URL) for the given song ids.
  Future<List<Track>> details(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final out = <Track>[];
    for (var i = 0; i < ids.length; i += 40) {
      final chunk = ids.sublist(i, i + 40 > ids.length ? ids.length : i + 40);
      final j = await _get('song.getDetails', {'pids': chunk.join(',')}, ttl: const Duration(hours: 1));
      out.addAll(_tracks(j['songs']));
    }
    return out;
  }

  Future<String?> lyrics(String id) async {
    try {
      final j = await _get('lyrics.getLyrics', {'lyrics_id': id}, ttl: const Duration(hours: 6));
      final l = j['lyrics'];
      if (l is String && l.trim().isNotEmpty) {
        return l.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      }
    } catch (_) {}
    return null;
  }

  // ---- radio (used by the recommender as its candidate pool) ----
  /// Similar-sounding songs for one or more seed songs.
  Future<List<Track>> radio(List<String> seedIds, {String language = 'hindi', int count = 25}) async {
    if (seedIds.isEmpty) return const [];
    final created = await _get(
      'webradio.createEntityStation',
      {
        'entity_id': jsonEncode(seedIds),
        'entity_type': 'queue',
        'language': language,
        'ctx': 'android',
      },
      ttl: const Duration(minutes: 30),
    );
    final sid = created is Map ? created['stationid'] : null;
    if (sid == null) return const [];
    final j = await _get(
      'webradio.getSong',
      {'stationid': '$sid', 'k': '$count', 'ctx': 'android'},
      ttl: const Duration(seconds: 1),
    );
    if (j is! Map) return const [];
    final out = <Track>[];
    for (final v in j.values) {
      if (v is Map && v['song'] is Map) {
        final t = Track.fromJson(Map<String, dynamic>.from(v['song']));
        if (t.id.isNotEmpty) out.add(t);
      }
    }
    return out;
  }

  // ---- home ----
  Future<HomeData> home(List<String> languages) async {
    final cookie = 'L=${languages.isEmpty ? 'hindi' : languages.join(',')}';
    final j = await _get('webapi.getLaunchData', {}, cookie: cookie, ttl: const Duration(minutes: 20));
    if (j is! Map) return const HomeData();
    return HomeData(
      trending: _cards(j['new_trending']),
      newAlbums: _cards(j['new_albums']),
      playlists: _cards(j['top_playlists']),
      charts: _cards(j['charts']),
      artists: _artistCards(j['artist_recos']),
    );
  }

  // ---- new releases ----
  /// The catalogue's newest albums and singles in [languages], newest first.
  /// Cached only briefly, so what just came out shows up soon after.
  Future<List<MediaCard>> newReleases(List<String> languages, {int page = 1, int n = 40, bool force = false}) async {
    final cookie = 'L=${languages.isEmpty ? 'hindi' : languages.join(',')}';
    final j = await _get('content.getAlbums', {'n': '$n', 'p': '$page'}, cookie: cookie, ttl: const Duration(minutes: 5), force: force);
    return sortByRelease(_cards(j is Map ? j['data'] : j));
  }

  /// Newest first; undated cards keep their place at the end.
  static List<MediaCard> sortByRelease(List<MediaCard> cards) {
    final dated = cards.where((c) => c.released != null).toList()..sort((a, b) => b.released!.compareTo(a.released!));
    return [...dated, ...cards.where((c) => c.released == null)];
  }

  /// This year's songs in a language the release feed doesn't cover
  /// (Korean, Japanese, French...), found by searching and kept only when
  /// both the language and the year match.
  Future<List<Track>> latestSongs(String language, {DateTime? now}) async {
    final year = (now ?? DateTime.now()).year;
    final pages = await Future.wait([
      for (final p in [1, 2]) searchSongs('$language $year', n: 50, page: p).catchError((_) => <Track>[]),
    ]);
    return freshInLanguage([for (final l in pages) ...l], language, year);
  }

  /// Keeps [year]'s songs in [language] (last year's too, early in the year
  /// when there are few), one copy of each title per artist.
  static List<Track> freshInLanguage(List<Track> songs, String language, int year) {
    final inLang = songs.where((t) => t.language == language && t.isPlayable).toList();
    var fresh = inLang.where((t) => t.year >= year).toList();
    if (fresh.length < 10) fresh = inLang.where((t) => t.year >= year - 1).toList();
    final seen = <String>{};
    return [
      for (final t in fresh)
        if (seen.add(t.sameSongKey)) t,
    ];
  }

  void dispose() => _client.close();
}

class _Cached {
  final dynamic value;
  final DateTime expires;
  _Cached(this.value, this.expires);
}
