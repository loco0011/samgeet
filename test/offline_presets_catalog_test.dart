import 'dart:convert';
import 'dart:io';

import 'package:dart_des/dart_des.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/catalog.dart';
import 'package:samgeet/data/download_service.dart';
import 'package:samgeet/data/saavn_api.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/player/audio_fx.dart';
import 'package:samgeet/ui/screens/category_screen.dart';
import 'package:samgeet/ui/screens/new_releases_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The catalogue's encrypted form of a stream address.
String encrypt(String url) {
  final des = DES(key: utf8.encode('38346591'), mode: DESMode.ECB, paddingType: DESPaddingType.PKCS5);
  return base64.encode(des.encrypt(utf8.encode(url)));
}

Track song(String id, {String title = '', String artist = 'A', String language = 'hindi', int year = 2026, bool playable = true, bool has320 = true}) => Track(
      id: id,
      title: title.isEmpty ? 'Song $id' : title,
      artists: [ArtistRef(id: 'a-$artist', name: artist)],
      language: language,
      year: year,
      image: 'https://c.saavncdn.com/1/$id-150x150.jpg',
      encryptedUrl: playable ? encrypt('https://aac.saavncdn.com/1/${id}_160.mp4') : '',
      has320: has320,
    );

void main() {
  group('Equalizer presets of your own', () {
    test('survive a save and load, boost included', () {
      const p = EqPreset('my:1', 'Car bass', [5, 3, 0, -1, 2], boost: 2.5);
      final back = AudioFx.decodeMine(AudioFx.encodeMine([p]));
      expect(back, hasLength(1));
      expect(back.first.label, 'Car bass');
      expect(back.first.curve, [5, 3, 0, -1, 2]);
      expect(back.first.boost, 2.5);
      expect(back.first.isMine, isTrue);
    });

    test('bad or foreign entries are skipped, broken data gives none', () {
      final raw = jsonEncode([
        {'id': 'bass', 'label': 'Pretends to be built in', 'curve': [1, 2]},
        {'id': 'my:2', 'label': '  ', 'curve': [1, 2]},
        {'id': 'my:3', 'label': 'No curve', 'curve': []},
        {'id': 'my:4', 'label': 'Good', 'curve': [1, 2, 3]},
      ]);
      expect(AudioFx.decodeMine(raw).map((p) => p.id), ['my:4']);
      expect(AudioFx.decodeMine('not json'), isEmpty);
      expect(AudioFx.decodeMine(null), isEmpty);
    });

    test('a saved curve stretches to phones with more bands', () {
      const p = EqPreset('my:1', 'x', [0, 10]);
      expect(p.gainAt(0, 3), 0);
      expect(p.gainAt(1, 3), 5);
      expect(p.gainAt(2, 3), 10);
    });
  });

  group('Category songs', () {
    const korean = Category(id: 'k', title: 'K', query: 'k', icon: Icons.star, colors: [Colors.red, Colors.blue], language: 'korean', strictLanguage: true);

    test('searches take turns, and re-uploads of one song are dropped', () {
      final a = [song('1', title: 'Golden', artist: 'X'), song('2')];
      final b = [song('3', title: 'golden', artist: 'X'), song('4')];
      final mixed = mixCategorySongs(Catalog.chill, searches: [a, b]);
      expect(mixed.map((t) => t.id), ['1', '2', '4']);
    });

    test('hand-picked songs come first, unplayable ones never show', () {
      final mixed = mixCategorySongs(Catalog.chill, picks: [song('p')], searches: [
        [song('1'), song('x', playable: false)],
      ]);
      expect(mixed.map((t) => t.id), ['p', '1']);
    });

    test('strict language keeps only that language, unless too few are left', () {
      final many = [for (var i = 0; i < 10; i++) song('k$i', language: 'korean'), song('e', language: 'english')];
      expect(mixCategorySongs(korean, searches: [many]).any((t) => t.language == 'english'), isFalse);
      final few = [song('k', language: 'korean'), song('e', language: 'english')];
      expect(mixCategorySongs(korean, searches: [few]), hasLength(2));
    });

    test('the catalogue has no two different tiles sharing an id', () {
      final seen = <String, Category>{};
      for (final g in Catalog.groups) {
        for (final c in g.items) {
          final prev = seen[c.id];
          expect(prev == null || identical(prev, c), isTrue, reason: 'id ${c.id} used twice');
          seen[c.id] = c;
          expect(c.songQueries.first, isNotEmpty);
        }
      }
      expect(Catalog.groups.map((g) => g.id), containsAll(['korean', 'classical', 'folk', 'world']));
    });
  });

  group('New releases', () {
    test('newest first, undated at the end', () {
      const a = MediaCard(kind: CardKind.album, id: 'a', title: 'A', releaseDate: '2026-09-01');
      const b = MediaCard(kind: CardKind.song, id: 'b', title: 'B', releaseDate: '2026-09-28');
      const c = MediaCard(kind: CardKind.album, id: 'c', title: 'C');
      expect(SaavnApi.sortByRelease([a, c, b]).map((x) => x.id), ['b', 'a', 'c']);
    });

    test('release cards read their date, language and artists', () {
      final card = MediaCard.fromJson({
        'id': '1',
        'title': 'Bass Persuades',
        'type': 'album',
        'subtitle': '',
        'language': 'English',
        'more_info': {
          'release_date': '2026-09-18',
          'artistMap': {
            'artists': [
              {'name': 'Miley Cyrus'},
            ],
          },
        },
      })!;
      expect(card.released, DateTime(2026, 9, 18));
      expect(card.language, 'english');
      expect(card.subtitle, 'Miley Cyrus');
    });

    test('world languages keep this year\'s songs in that language, one copy each', () {
      final found = [
        song('1', title: 'Golden', language: 'korean'),
        song('2', title: 'Golden', language: 'korean'),
        song('3', language: 'english'),
        song('4', language: 'korean', year: 2019),
        for (var i = 0; i < 10; i++) song('n$i', language: 'korean'),
      ];
      final fresh = SaavnApi.freshInLanguage(found, 'korean', 2026);
      expect(fresh.map((t) => t.id), isNot(contains('2')));
      expect(fresh.map((t) => t.id), isNot(contains('3')));
      expect(fresh.map((t) => t.id), isNot(contains('4')));
      expect(fresh, hasLength(11));
    });

    test('headings: today, yesterday, this week', () {
      final now = DateTime(2026, 9, 30, 10);
      expect(releaseHeading(DateTime(2026, 9, 30), now), 'Today');
      expect(releaseHeading(DateTime(2026, 9, 29), now), 'Yesterday');
      expect(releaseHeading(DateTime(2026, 9, 25), now), 'This week');
      expect(releaseHeading(DateTime(2026, 9, 20), now), 'Last week');
      expect(releaseHeading(null, now), 'Recently');
    });
  });

  group('Downloads', () {
    late Directory dir;
    late SharedPreferences prefs;
    final requested = <String>[];

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('samgeet-dl');
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      requested.clear();
    });

    tearDown(() => dir.delete(recursive: true));

    DownloadService service({int status = 200}) {
      final client = MockClient((req) async {
        requested.add(req.url.toString());
        if (req.url.path.endsWith('.jpg')) return http.Response.bytes([1, 2, 3], 200);
        return http.Response.bytes(List.filled(5000, 7), status);
      });
      return DownloadService(prefs, SaavnApi(client: client), client: client, dir: () async => dir);
    }

    Future<void> settle(DownloadService d) async {
      for (var i = 0; i < 400 && d.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('a song is saved at the chosen quality, with its cover, and listed', () async {
      final d = service();
      await d.init();
      d.download(song('s1'));
      expect(d.stateOf('s1'), anyOf(DownloadState.queued, DownloadState.downloading));
      await settle(d);

      expect(d.isDownloaded('s1'), isTrue);
      expect(requested.first, endsWith('s1_320.mp4')); // high quality by default
      expect(await File(d.fileFor('s1')!).length(), 5000);
      expect(d.artFor('s1'), isNotNull);
      expect(DownloadService.localArt('https://c.saavncdn.com/1/s1-500x500.jpg'), d.artFor('s1'));
      expect(d.totalBytes, 5000);

      // It's remembered across restarts...
      final again = service();
      await again.init();
      expect(again.isDownloaded('s1'), isTrue);
      expect(again.songs.single.title, 'Song s1');

      // ...and removing it deletes the file.
      final file = again.fileFor('s1')!;
      await again.remove('s1');
      expect(await File(file).exists(), isFalse);
      expect(again.count, 0);
    });

    test('songs without 320 kbps are saved at 160', () async {
      final d = service();
      await d.init();
      d.download(song('s2', has320: false));
      await settle(d);
      expect(requested.first, endsWith('s2_160.mp4'));
      expect(d.items.single.kbps, 160);
    });

    test('a failed download leaves nothing behind and says so', () async {
      final d = service(status: 404);
      await d.init();
      final messages = <String>[];
      d.messages.listen(messages.add);
      d.download(song('s3'));
      await settle(d);
      expect(d.isDownloaded('s3'), isFalse);
      expect(d.stateOf('s3'), DownloadState.failed);
      expect(dir.listSync(), isEmpty);
      expect(messages.single, contains('Couldn\'t download'));
    });

    test('files deleted outside the app drop off the list', () async {
      final d = service();
      await d.init();
      d.download(song('s4'));
      await settle(d);
      await File(d.fileFor('s4')!).delete();
      final again = service();
      await again.init();
      expect(again.count, 0);
      expect(DownloadService.decodeIndex(prefs.getString(DownloadService.indexPref)), isEmpty);
    });
  });
}
