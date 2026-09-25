import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:samgeet/data/library_store.dart';
import 'package:samgeet/data/profile.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/engine/mood.dart';
import 'package:samgeet/ui/mood_theme.dart';

Track song(String title, {String album = '', int year = 2015, String artist = 'X'}) => Track(
      id: title,
      title: title,
      album: album,
      year: year,
      artists: [ArtistRef(id: 'a_$artist', name: artist)],
      encryptedUrl: 'x',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mood detection', () {
    test('reads sad songs from the title', () {
      expect(MoodDetector.detect(song('Bekhayali')), Mood.sad);
      expect(MoodDetector.detect(song('Judai', album: 'Badlapur')), Mood.sad);
    });

    test('reads romantic songs', () {
      expect(MoodDetector.detect(song('Tum Hi Ho')), Mood.romantic);
      expect(MoodDetector.detect(song('Pyar Hua Ikrar Hua')), Mood.romantic);
    });

    test('reads party and devotional songs', () {
      expect(MoodDetector.detect(song('Kala Chashma')), Mood.party);
      expect(MoodDetector.detect(song('Hanuman Chalisa')), Mood.devotional);
    });

    test('the category you started from steers a neutral title', () {
      expect(MoodDetector.detect(song('Kuch Kuch'), context: 'sad heartbreak songs'), Mood.sad);
      expect(MoodDetector.detect(song('Kuch Kuch'), context: 'lofi hindi'), Mood.chill);
    });

    test('old songs lean nostalgic, and unknown songs have no mood', () {
      expect(MoodDetector.detect(song('Aaj Ki Raat', year: 1962)), Mood.nostalgic);
      expect(MoodDetector.detect(song('Zzz Qqq', year: 2020)), isNull);
    });

    test('short words do not match inside longer ones', () {
      // "ram" is a devotional keyword but must not fire for "Ramesh" / "Program".
      expect(MoodDetector.detect(song('Ramesh Program', year: 2020)), isNull);
    });
  });

  group('who gets the mood colours', () {
    test('guests always get the default look, whatever the mood', () {
      for (final m in [null, ...Mood.values]) {
        expect(MoodPalette.resolve(mood: m, signedIn: false, accent: 'emerald'), MoodPalette.ember);
      }
    });

    test('signed-in listeners get the mood palette', () {
      final p = MoodPalette.resolve(mood: Mood.sad, signedIn: true, accent: 'ember');
      expect(p.label, 'Melancholy');
      expect(p, isNot(MoodPalette.ember));
    });

    test('with no clear mood, signed-in listeners get their chosen accent', () {
      expect(MoodPalette.resolve(mood: null, signedIn: true, accent: 'emerald'), MoodPalette.emerald);
      expect(MoodPalette.resolve(mood: null, signedIn: true, accent: 'nonsense'), MoodPalette.ember);
    });

    test('every palette is dark enough for white text', () {
      final all = [...MoodPalette.accents.values, for (final m in Mood.values) MoodPalette.of(m)];
      for (final pal in all) {
        for (final c in pal.colors) {
          expect(c.computeLuminance(), lessThan(0.22), reason: '${pal.label} has a colour that is too bright');
        }
      }
    });
  });

  group('profile and the guest playlist limit', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guests can hold 5 songs but not 6', () async {
      final lib = await LibraryStore.load();
      expect(lib.signedIn, isFalse);
      expect(lib.canHold(5), isTrue);
      expect(lib.canHold(6), isFalse);
    });

    test('signing in removes the limit', () async {
      final lib = await LibraryStore.load();
      lib.signIn(Profile(name: 'Asha', createdAt: 1));
      expect(lib.signedIn, isTrue);
      expect(lib.canHold(500), isTrue);
    });

    test('preferences seed the languages and the taste profile', () async {
      final lib = await LibraryStore.load();
      lib.signIn(Profile(name: 'Asha', languages: ['bengali'], artists: ['Kishore Kumar'], createdAt: 1));
      expect(lib.languages, ['bengali']);
      expect(lib.taste.topArtists().map((a) => a.name), contains('Kishore Kumar'));
    });

    test('the profile survives a restart and sign-out clears it', () async {
      var lib = await LibraryStore.load();
      lib.signIn(Profile(name: 'Asha', email: 'a@b.co', moods: ['romantic'], createdAt: 7));
      await lib.flush();
      lib = await LibraryStore.load();
      expect(lib.profile?.name, 'Asha');
      expect(lib.profile?.moods, ['romantic']);
      await lib.signOut();
      await lib.flush();
      lib = await LibraryStore.load();
      expect(lib.signedIn, isFalse);
    });

    test('initials', () {
      expect(Profile(name: 'Sambit Das', createdAt: 1).initials, 'SD');
      expect(Profile(name: 'asha', createdAt: 1).initials, 'A');
    });
  });
}
