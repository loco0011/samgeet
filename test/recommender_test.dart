import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/engine/recommender.dart';
import 'package:samgeet/engine/taste_profile.dart';

Track t(String id, {String lang = 'hindi', int year = 2013, List<String> artists = const ['A'], String album = '', int plays = 1000000}) =>
    Track(
      id: id,
      title: 'Song $id',
      artists: [for (final a in artists) ArtistRef(id: 'id_$a', name: a)],
      language: lang,
      year: year,
      albumId: album,
      playCount: plays,
      encryptedUrl: 'x',
    );

List<Candidate> radio(List<Track> ts) =>
    [for (var i = 0; i < ts.length; i++) Candidate(ts[i], CandidateSource.radio, 1 - i / ts.length)];

void main() {
  Random rng() => Random(7);

  group('similarity', () {
    test('same language + artist + era beats unrelated song', () {
      final seed = t('s', artists: ['Arijit'], year: 2013);
      final close = t('c', artists: ['Arijit'], year: 2014);
      final far = t('f', lang: 'english', artists: ['Other'], year: 1975);
      expect(Recommender.similarity(seed, close), greaterThan(Recommender.similarity(seed, far)));
      expect(Recommender.similarity(seed, far), lessThan(0.1));
    });

    test('is symmetric and bounded', () {
      final a = t('a', artists: ['X', 'Y'], album: 'al');
      final b = t('b', artists: ['Y'], album: 'al');
      expect(Recommender.similarity(a, b), Recommender.similarity(b, a));
      expect(Recommender.similarity(a, b), inInclusiveRange(0, 1));
    });
  });

  group('rank', () {
    test('never returns the seed, excluded or duplicate songs', () {
      final seed = t('s');
      final pool = radio([t('s'), t('1'), t('1'), t('2'), t('3')]);
      final out = Recommender.rank(seed: seed, pool: pool, taste: TasteProfile(), exclude: {'2'}, rng: rng());
      expect(out.map((x) => x.id), unorderedEquals(['1', '3']));
    });

    test('keeps the queue in the same language as the seed', () {
      final seed = t('s', lang: 'bengali', artists: ['Anupam']);
      final pool = radio([
        t('en1', lang: 'english', artists: ['E1']),
        t('bn1', lang: 'bengali', artists: ['B1']),
        t('en2', lang: 'english', artists: ['E2']),
        t('bn2', lang: 'bengali', artists: ['B2']),
      ]);
      final out = Recommender.rank(seed: seed, pool: pool, taste: TasteProfile(), take: 2, rng: rng());
      expect(out.map((x) => x.language), everyElement('bengali'));
    });

    test('avoids long same-artist streaks', () {
      final seed = t('s', artists: ['Arijit']);
      final pool = [
        for (var i = 0; i < 8; i++) Candidate(t('a$i', artists: ['Arijit']), CandidateSource.radio, 0.9),
        for (var i = 0; i < 6; i++) Candidate(t('o$i', artists: ['Other$i']), CandidateSource.radio, 0.7),
      ];
      final out = Recommender.rank(seed: seed, pool: pool, taste: TasteProfile(), take: 8, rng: rng());
      var longest = 0, run = 0;
      for (final s in out) {
        run = s.artists.first.name == 'Arijit' ? run + 1 : 0;
        longest = max(longest, run);
      }
      expect(longest, lessThanOrEqualTo(2));
    });

    test('songs the listener recently skipped are pushed down', () {
      final seed = t('s');
      final pool = radio([t('skipped', artists: ['X']), t('fine', artists: ['Y'])]);
      final out = Recommender.rank(seed: seed, pool: pool, taste: TasteProfile(), skipped: {'skipped'}, take: 2, rng: rng());
      expect(out.first.id, 'fine');
    });
  });

  group('taste profile', () {
    test('learns a favourite artist and ranks their songs higher', () {
      final p = TasteProfile();
      final loved = t('l', artists: ['Kishore'], lang: 'hindi', year: 1975);
      for (var i = 0; i < 4; i++) {
        p.record(loved, TasteEvent.completed);
      }
      p.record(loved, TasteEvent.liked);
      expect(p.topArtists().first.name, 'Kishore');
      final seed = t('s');
      final out = Recommender.rank(
        seed: seed,
        pool: [
          Candidate(t('meh', artists: ['Nobody']), CandidateSource.radio, 0.6),
          Candidate(t('fav', artists: ['Kishore'], year: 1978), CandidateSource.radio, 0.5),
        ],
        taste: p,
        take: 2,
        rng: rng(),
      );
      expect(out.first.id, 'fav');
    });

    test('skips make an artist less likely', () {
      final p = TasteProfile();
      final bad = t('b', artists: ['Annoying']);
      p.record(bad, TasteEvent.skipped);
      p.record(bad, TasteEvent.skipped);
      expect(p.affinity(bad), lessThan(0));
    });

    test('old signals fade over time (30 day half-life)', () {
      final p = TasteProfile();
      final tr = t('x', artists: ['Old']);
      final then = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      p.record(tr, TasteEvent.liked, nowMs: then);
      final fresh = p.affinity(tr, nowMs: then);
      final later = p.affinity(tr, nowMs: then + 90 * Duration.millisecondsPerDay);
      expect(later, lessThan(fresh / 3));
    });

    test('survives a JSON round trip', () {
      final p = TasteProfile();
      p.record(t('a', artists: ['Shreya']), TasteEvent.liked);
      final q = TasteProfile.fromJson(p.toJson());
      expect(q.topArtists().first.name, 'Shreya');
      expect(q.affinity(t('z', artists: ['Shreya'])), closeTo(p.affinity(t('z', artists: ['Shreya'])), 1e-9));
    });
  });

  group('track parsing', () {
    const enc =
        'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyRofh8YQPTqjR2tIxTYXqGEQHgqnNfsetouo4rsD0s4RZKObWAyHrEhw7tS9a8Gtq';
    Track withUrl({required bool has320}) =>
        Track(id: 'q', title: 'Tum Hi Ho', encryptedUrl: enc, has320: has320);

    test('decrypts the real stream URL and picks the requested quality', () {
      final tr = withUrl(has320: true);
      expect(tr.streamUrl(AudioQuality.high), endsWith('5c5ea5cc00e3bff45616013226f376fe_320.mp4'));
      expect(tr.streamUrl(AudioQuality.medium), endsWith('_160.mp4'));
      expect(tr.streamUrl(AudioQuality.low), endsWith('_96.mp4'));
    });

    test('falls back to 160 when 320 is unavailable', () {
      expect(withUrl(has320: false).streamUrl(AudioQuality.high), endsWith('_160.mp4'));
    });

    test('malformed encrypted URLs yield empty instead of crashing', () {
      expect(t('q').streamUrl(AudioQuality.high), '');
    });
  });
}
