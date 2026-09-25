import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/deep_link.dart';
import 'package:samgeet/data/share_service.dart';
import 'package:samgeet/data/track.dart';

const song = Track(id: 'abc123', title: 'Kesariya', artists: [ArtistRef(id: '1', name: 'Arijit Singh')], album: 'Brahmastra');

void main() {
  group('finding a short link', () {
    test('on its own, inside a message, and from the page\'s button', () {
      expect(shortLinkCode('https://api.sambitmaity.fun/s/k7qm2xa'), 'k7qm2xa');
      expect(shortLinkCode('🎧 Road trip · 12 songs\nOpen in Samgeet 👉 https://api.sambitmaity.fun/s/k7qm2xa'), 'k7qm2xa');
      expect(shortLinkCode('samgeet://share?c=k7qm2xa'), 'k7qm2xa');
    });

    test('ignores other hosts and malformed codes', () {
      expect(shortLinkCode('https://evil.example/s/k7qm2xa'), isNull);
      expect(shortLinkCode('https://api.sambitmaity.fun/s/k7qm2xa9'), isNull); // too long
      expect(shortLinkCode('https://api.sambitmaity.fun/s/K7QM2XA'), isNull); // not our alphabet
      expect(shortLinkCode('https://api.sambitmaity.fun/s/k0qm1xa'), isNull); // 0 and 1 are never used
      expect(shortLinkCode('samgeet://share?c=../../x'), isNull);
    });
  });

  group('making a short link', () {
    test('uses the server\'s code', () async {
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{"code":"k7qm2xa"}', 200);
      });
      expect(await ShareService.shortSongLink(song, client: client), 'https://api.sambitmaity.fun/s/k7qm2xa');
      expect(sent, containsPair('t', 'song'));
      expect(sent, containsPair('id', 'abc123'));
    });

    test('falls back to the long link when the server can\'t be reached or answers oddly', () async {
      final offline = MockClient((_) async => throw Exception('no network'));
      expect(await ShareService.shortSongLink(song, client: offline), ShareService.songLink(song));
      final odd = MockClient((_) async => http.Response('{"code":"<script>"}', 200));
      expect(await ShareService.shortPlaylistLink('Mix', [song], client: odd), ShareService.playlistLink('Mix', [song]));
    });
  });

  group('opening a short link', () {
    test('a song', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://api.sambitmaity.fun/link.php?c=k7qm2xa');
        return http.Response('{"t":"song","id":"abc123","s":"Kesariya"}', 200);
      });
      final link = await resolveShortLink('k7qm2xa', client: client);
      expect(link, isA<SharedSong>());
      expect((link as SharedSong).id, 'abc123');
      expect(link.title, 'Kesariya');
    });

    test('a playlist, with bad song ids dropped', () async {
      final client = MockClient((_) async => http.Response('{"t":"playlist","n":"Road trip","ids":["a1","b 2","c3"]}', 200));
      final link = await resolveShortLink('k7qm2xa', client: client) as SharedPlaylist;
      expect(link.name, 'Road trip');
      expect(link.ids, ['a1', 'c3']);
    });

    test('unknown, broken or unreachable: nothing', () async {
      expect(await resolveShortLink('k7qm2xa', client: MockClient((_) async => http.Response('{"error":"not_found"}', 404))), isNull);
      expect(await resolveShortLink('k7qm2xa', client: MockClient((_) async => http.Response('not json', 200))), isNull);
      expect(await resolveShortLink('k7qm2xa', client: MockClient((_) async => throw Exception('offline'))), isNull);
      expect(await resolveShortLink('../etc', client: MockClient((_) async => http.Response('{}', 200))), isNull);
    });
  });
}
