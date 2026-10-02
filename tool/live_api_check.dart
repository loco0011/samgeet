// Hits the real server. Run manually:  flutter test tool/live_api_check.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/catalog.dart';
import 'package:samgeet/data/download_service.dart';
import 'package:samgeet/data/saavn_api.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/ui/screens/category_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final api = SaavnApi();
  setUpAll(() => HttpOverrides.global = null);

  test('every catalog category returns playlists and songs', () async {
    final weak = <String>[];
    final done = <String>{};
    for (final g in Catalog.groups) {
      for (final c in g.items) {
        if (!done.add(c.id)) continue;
        final pl = c.playlists ? await api.searchPlaylists(c.query, n: 10) : const <MediaCard>[];
        // The same searches and mixing the category page uses.
        final searches = [
          for (final (i, q) in c.songQueries.indexed) await api.searchSongs(q, n: i == 0 ? 40 : 25).catchError((_) => <Track>[]),
        ];
        final songs = mixCategorySongs(c, searches: searches);
        final playable = songs.length;
        final langs = <String, int>{};
        for (final s in songs) { langs[s.language] = (langs[s.language] ?? 0) + 1; }
        final top = (langs.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(2).map((e) => '${e.key}:${e.value}').join(',');
        final flag = ((c.playlists && pl.length < 3) || playable < 15) ? '  <-- WEAK' : '';
        // ignore: avoid_print
        print('${c.id.padRight(16)} playlists=${pl.length.toString().padLeft(2)} songs=${songs.length.toString().padLeft(2)} playable=$playable  [$top]$flag');
        if (flag.isNotEmpty) weak.add(c.id);
      }
    }
    // ignore: avoid_print
    print('WEAK: $weak');
  }, timeout: const Timeout(Duration(minutes: 15)));

  test('new releases: fresh, dated, in every listed language', () async {
    final now = DateTime.now();
    for (final lang in Catalog.releaseFeedLanguages.keys) {
      final r = await api.newReleases([lang], n: 20);
      final newest = r.firstOrNull?.released;
      // ignore: avoid_print
      print('${lang.padRight(11)} ${r.length.toString().padLeft(2)} releases, newest ${r.firstOrNull?.releaseDate} ${r.firstOrNull?.title}');
      expect(r, isNotEmpty, reason: lang);
      expect(newest, isNotNull, reason: lang);
      expect(now.difference(newest!).inDays, lessThan(45), reason: '$lang is stale');
    }
    for (final lang in Catalog.releaseSearchLanguages.keys) {
      final s = await api.latestSongs(lang);
      // ignore: avoid_print
      print('${lang.padRight(11)} ${s.length.toString().padLeft(2)} songs this year: ${s.take(3).map((t) => t.title).join(' ; ')}');
      expect(s.length, greaterThan(5), reason: lang);
      expect(s.every((t) => t.language == lang), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a real song downloads at 320 kbps and matches the stream', () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('samgeet-live-dl');
    final dl = DownloadService(await SharedPreferences.getInstance(), api, dir: () async => dir);
    await dl.init();
    final t = (await api.searchSongs('kesariya arijit', n: 5)).firstWhere((t) => t.isPlayable && t.has320);
    dl.download(t);
    for (var i = 0; i < 600 && dl.busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final saved = dl.items.single;
    final head = await File(saved.file).openRead(0, 12).expand((b) => b).toList();
    // ignore: avoid_print
    print('${t.title}: ${saved.kbps} kbps, ${DownloadService.size(saved.bytes)} for ${t.durationSec}s, cover ${saved.art.isNotEmpty}');
    expect(saved.kbps, 320);
    expect(String.fromCharCodes(head.sublist(4, 8)), 'ftyp'); // an MP4/AAC file, as streamed
    expect(saved.art, isNotEmpty);
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));

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
