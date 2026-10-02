// Live check of song search against the real catalogue (needs internet):
//   flutter test tool/search_live_check.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/saavn_api.dart';

void main() {
  final api = SaavnApi();

  Future<void> finds(String query, String expectedTitle, {bool quick = false}) async {
    final watch = Stopwatch()..start();
    final r = await api.findSongs(query, quick: quick);
    final top = r.songs.take(3).map((t) => t.title).toList();
    // ignore: avoid_print
    print('${quick ? 'typing' : 'search'} "$query" -> $top in ${watch.elapsedMilliseconds} ms');
    expect(top.any((t) => t.toLowerCase().contains(expectedTitle)), isTrue, reason: 'top 3 for "$query": $top');
  }

  test('exact and mixed-case names', () async {
    await finds('Kesariya', 'kesariya');
    await finds('  TUM HI   HO ', 'tum hi ho');
  });

  test('misspellings and a wrong word', () async {
    await finds('kesarya', 'kesariya');
    await finds('blinding lite weeknd', 'blinding lights');
  });

  test('a line from the lyrics', () async {
    await finds('mujhko itna bataaye koi', 'kesariya');
  });

  test('while typing (fast path)', () async {
    await finds('chaleya', 'chaleya', quick: true);
    await finds('pasoori', 'pasoori', quick: true);
  });
}
