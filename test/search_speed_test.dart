import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/saavn_api.dart';

Map<String, Object> songJson(String id, String title) => {
      'id': id,
      'title': title,
      'type': 'song',
      'more_info': {
        'encrypted_media_url': 'x',
        'artistMap': {
          'primary_artists': [{'id': 'a1', 'name': 'Arijit Singh'}],
        },
      },
    };

void main() {
  group('catalogue requests', () {
    test('the same search made twice at once goes over the network once', () async {
      var calls = 0;
      final gate = Completer<void>();
      final api = SaavnApi(client: MockClient((r) async {
        calls++;
        await gate.future;
        return http.Response(jsonEncode({'results': [songJson('s1', 'Kesariya')]}), 200);
      }));
      final a = api.searchSongs('kesariya');
      final b = api.searchSongs('kesariya');
      gate.complete();
      expect((await a).single.id, 's1');
      expect((await b).single.id, 's1');
      expect(calls, 1);
    });

    test('capitals and extra spaces share one cached search', () async {
      final queries = <String>[];
      final api = SaavnApi(client: MockClient((r) async {
        queries.add(r.url.queryParameters['q'] ?? '');
        return http.Response(jsonEncode({'results': [songJson('s1', 'Tum Hi Ho')]}), 200);
      }));
      await api.searchSongs('Arijit  Singh ');
      await api.searchSongs('arijit singh');
      expect(queries, ['arijit singh']);
    });

    test('a failed request ends with an error (it never hangs) and is tried again next time', () async {
      var calls = 0;
      final api = SaavnApi(client: MockClient((r) async {
        calls++;
        return http.Response('nope', 500);
      }));
      await expectLater(api.searchSongs('x').timeout(const Duration(seconds: 5)), throwsA(isA<ApiException>()));
      final before = calls;
      await expectLater(api.searchSongs('x').timeout(const Duration(seconds: 5)), throwsA(isA<ApiException>()));
      expect(calls, greaterThan(before));
    });
  });

  group('search while typing', () {
    test('a query with good direct results costs two requests, and pressing search reuses them', () async {
      final calls = <String>[];
      final api = SaavnApi(client: MockClient((r) async {
        final p = r.url.queryParameters;
        final call = p['__call']!;
        calls.add('$call:${p['q'] ?? p['query'] ?? ''}');
        if (call == 'autocomplete.get') return http.Response(jsonEncode({'songs': {'data': []}}), 200);
        return http.Response(jsonEncode({'results': [for (var i = 0; i < 3; i++) songJson('s$i', 'Chaleya $i')]}), 200);
      }));
      final quick = await api.findSongs('Chaleya', quick: true);
      expect(quick.songs, isNotEmpty);
      expect(calls, unorderedEquals(['search.getResults:chaleya', 'autocomplete.get:chaleya']));
      await api.findSongs('chaleya'); // pressing search: the typed query isn't fetched again
      expect(calls.where((c) => c == 'search.getResults:chaleya'), hasLength(1));
      expect(calls.where((c) => c == 'autocomplete.get:chaleya'), hasLength(1));
    });
  });
}
