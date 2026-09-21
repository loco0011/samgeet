// Hits the real server. Run manually:  flutter test tool/live_api_check.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/catalog.dart';
import 'package:samgeet/data/saavn_api.dart';

void main() {
  final api = SaavnApi();
  setUpAll(() => HttpOverrides.global = null);

  test('every catalog category returns playlists and songs', () async {
    final weak = <String>[];
    for (final g in Catalog.groups) {
      for (final c in g.items) {
        final pl = await api.searchPlaylists(c.query, n: 10);
        final songs = await api.searchSongs(c.songQuery ?? c.query, n: 20);
        final playable = songs.where((s) => s.isPlayable).length;
        final langs = <String, int>{};
        for (final s in songs) { langs[s.language] = (langs[s.language] ?? 0) + 1; }
        final top = (langs.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(2).map((e) => '${e.key}:${e.value}').join(',');
        final flag = (pl.length < 3 || playable < 10) ? '  <-- WEAK' : '';
        // ignore: avoid_print
        print('${c.id.padRight(16)} playlists=${pl.length.toString().padLeft(2)} songs=${songs.length.toString().padLeft(2)} playable=$playable  [$top]$flag');
        if (flag.isNotEmpty) weak.add(c.id);
      }
    }
    // ignore: avoid_print
    print('WEAK: $weak');
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('artists resolve', () async {
    final missing = <String>[];
    for (final g in Catalog.artistGroups) {
      for (final n in g.names) {
        final r = await api.searchArtists(n, n: 3);
        if (r.isEmpty || !r.first.name.toLowerCase().contains(n.toLowerCase().split(' ').first.replaceAll('.', ''))) {
          missing.add('$n -> ${r.isEmpty ? "none" : r.first.name}');
        }
      }
    }
    // ignore: avoid_print
    print('ARTIST MISMATCH: $missing');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('detail endpoints parse', () async {
    final s = (await api.searchSongs('tum hi ho', n: 3)).first;
    final album = await api.album(s.albumId);
    final art = await api.artist(s.artists.first.id);
    final radio = await api.radio([s.id], language: s.language, count: 20);
    final lyr = await api.lyrics(s.id);
    final det = await api.details([s.id]);
    final home = await api.home(['hindi', 'bengali']);
    final pl = await api.playlist((await api.searchPlaylists('90s bollywood')).first.id);
    // ignore: avoid_print
    print('album "${album.title}" tracks=${album.tracks.length} playable=${album.tracks.where((t) => t.isPlayable).length}');
    // ignore: avoid_print
    print('artist "${art.artist.name}" top=${art.topSongs.length} albums=${art.albums.length} similar=${art.similar.length} followers=${art.followers}');
    // ignore: avoid_print
    print('radio=${radio.length} first=${radio.take(3).map((t) => "${t.title}/${t.artistLine}").toList()}');
    // ignore: avoid_print
    print('lyrics=${lyr == null ? "none" : "${lyr.length} chars"}  details=${det.length}');
    // ignore: avoid_print
    print('home trending=${home.trending.length} albums=${home.newAlbums.length} playlists=${home.playlists.length} charts=${home.charts.length} artists=${home.artists.length}');
    // ignore: avoid_print
    print('playlist "${pl.title}" tracks=${pl.tracks.length} playable=${pl.tracks.where((t) => t.isPlayable).length}');
    expect(album.tracks, isNotEmpty);
    expect(radio, isNotEmpty);
    expect(pl.tracks, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
