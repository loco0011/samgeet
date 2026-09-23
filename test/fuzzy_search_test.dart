import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/fuzzy.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/engine/recommender.dart';
import 'package:samgeet/engine/taste_profile.dart';

Track song(String id, String title, {List<String> artists = const ['Arijit Singh'], String album = ''}) => Track(
      id: id,
      title: title,
      artists: [for (final a in artists) ArtistRef(id: a, name: a)],
      album: album,
      language: 'hindi',
      encryptedUrl: 'x',
    );

void main() {
  group('Fuzzy.score', () {
    test('forgives misspellings and transliteration variants', () {
      expect(Fuzzy.score('chaliya', 'Chaleya'), greaterThan(0.6));
      expect(Fuzzy.score('fir bhi tumko chahunga', 'Phir Bhi Tumko Chaahunga'), greaterThan(0.85));
      expect(Fuzzy.score('kesarya', 'Kesariya'), greaterThan(0.8));
    });

    test('matches part of a title and ignores spacing mistakes', () {
      expect(Fuzzy.score('kesar', 'Kesariya (From "Brahmastra")'), greaterThan(0.85));
      expect(Fuzzy.score('tumhi ho', 'Tum Hi Ho'), greaterThan(0.9));
      expect(Fuzzy.score('mereya', 'Channa Mereya'), 1);
    });

    test('unrelated titles score low', () {
      expect(Fuzzy.score('kesariya', 'Shape of You'), lessThan(0.3));
    });

    test('songScore uses artist and album words too', () {
      final t = song('1', 'Blinding Lights', artists: ['The Weeknd']);
      expect(Fuzzy.songScore('blinding lite weeknd', t), greaterThan(0.75));
      expect(Fuzzy.songScore('blinding lite weeknd', song('2', 'Tum Hi Ho')), lessThan(0.3));
    });
  });

  test('dropOneWord gives each variant with one word left out', () {
    expect(Fuzzy.dropOneWord('blinding lite weeknd'), ['lite weeknd', 'blinding weeknd', 'blinding lite']);
    expect(Fuzzy.dropOneWord('kesariya'), isEmpty);
  });

  group('radio skips other versions of the same song', () {
    test('baseTitle strips decorations', () {
      expect(Recommender.baseTitle('Kesariya (Lofi Flip)'), 'kesariya');
      expect(Recommender.baseTitle('Apna Bana Le Piya - Jhankar Beats'), 'apnabanalepiya');
      expect(Recommender.baseTitle('আমি যে তোমার'), isNotEmpty);
    });

    test('rank drops remixes of the seed and keeps one version of each song', () {
      final seed = song('s', 'Kesariya');
      final pool = [
        for (final t in [
          song('a', 'Kesariya (Lofi Flip)'),
          song('b', 'Raabta', artists: ['X']),
          song('c', 'Raabta (Slowed)', artists: ['Y']),
          song('d', 'Tum Hi Ho', artists: ['Z']),
        ])
          Candidate(t, CandidateSource.radio, 1),
      ];
      final out = Recommender.rank(seed: seed, pool: pool, taste: TasteProfile());
      expect(out.map((t) => t.id), unorderedEquals(['b', 'd']));
    });
  });
}
