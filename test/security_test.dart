import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/share_service.dart';
import 'package:samgeet/data/track.dart';

void main() {
  group('playlist import treats pasted codes as untrusted', () {
    String code(Object payload) => 'samgeet://p/${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(payload))))}';

    test('a normal code still round-trips', () {
      final c = code({'n': 'Road trip', 'i': ['a', 'b', 'c']});
      final d = ShareService.decodePlaylist('hello $c bye')!;
      expect(d.name, 'Road trip');
      expect(d.ids, ['a', 'b', 'c']);
    });

    test('a decompression bomb is rejected instead of exhausting memory', () {
      // ~2 MB of zeros gzips to a couple of KB but expands far past the cap.
      final bomb = 'samgeet://p/${base64Url.encode(gzip.encode(List.filled(2 * 1024 * 1024, 0)))}';
      expect(ShareService.decodePlaylist(bomb), isNull);
    });

    test('an oversized code is rejected up front', () {
      expect(ShareService.decodePlaylist('samgeet://p/${'A' * (ShareService.maxCodeChars + 1)}'), isNull);
    });

    test('the number of songs and the name length are capped', () {
      final ids = List.generate(ShareService.maxSongs + 100, (i) => 'id$i');
      final d = ShareService.decodePlaylist(code({'n': 'x' * 300, 'i': ids}))!;
      expect(d.ids.length, ShareService.maxSongs);
      expect(d.name.length, 80);
    });

    test('garbage and empty lists are rejected', () {
      expect(ShareService.decodePlaylist('samgeet://p/not-a-real-code'), isNull);
      expect(ShareService.decodePlaylist(code({'n': 'Empty', 'i': []})), isNull);
    });
  });

  test('cleartext http links from the source are upgraded to https', () {
    expect(httpsOnly('http://c.saavncdn.com/a.jpg'), 'https://c.saavncdn.com/a.jpg');
    expect(httpsOnly('https://c.saavncdn.com/a.jpg'), 'https://c.saavncdn.com/a.jpg');
    expect(httpsOnly(''), '');
  });
}
