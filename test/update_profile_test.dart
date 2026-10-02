import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/library_store.dart';
import 'package:samgeet/data/profile.dart';
import 'package:samgeet/data/release_notes.dart';
import 'package:samgeet/data/update_service.dart';
import 'package:samgeet/ui/screens/sign_in_screen.dart' show isEmoji;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('update highlights', () {
    test('each bullet becomes its emoji and bold lead', () {
      final h = Highlight.parse('## Samgeet 9\n\n[required]\n\n- 🎨 **Make the player yours.** Four looks.\n- ⬇️ **Offline downloads.** Save songs.\n'
          '- Plain bullet with no bold lead. More text.\n\n### Install\nDownload it.');
      expect([for (final x in h) '${x.icon}|${x.title}'], ['🎨|Make the player yours', '⬇️|Offline downloads', '|Plain bullet with no bold lead']);
    });

    test('the bundled notes give short headlines for About', () {
      final h = Highlight.parse(kReleaseNotes);
      expect(h.length, greaterThanOrEqualTo(6));
      expect(h.every((x) => x.title.length <= 48 && x.icon.isNotEmpty), isTrue);
    });
  });

  group('required updates', () {
    Map<String, dynamic> release(String tag, {bool required = true}) => {
          'tag_name': tag,
          'html_url': 'https://github.com/loco0011/samgeet/releases/tag/$tag',
          'body': '${required ? '[required]\n' : ''}- 🎨 **New looks.** x',
          'assets': [
            {'name': 'Samgeet.apk', 'browser_download_url': 'https://github.com/loco0011/samgeet/releases/download/$tag/Samgeet.apk'},
          ],
        };

    test('show again on the next open, even within the 6-hour wait and offline', () async {
      SharedPreferences.setMockInitialValues({});
      var online = true;
      final client = MockClient((r) async {
        if (!online) throw http.ClientException('offline');
        return http.Response.bytes(utf8.encode(jsonEncode(release('v99.0.0'))), 200);
      });
      final first = await UpdateService(client: client).check();
      expect(first?.required, isTrue);
      expect(first!.highlights.single.title, 'New looks');
      online = false; // and inside the 6-hour window
      final again = await UpdateService(client: client).check();
      expect(again?.version, '99.0.0');
      expect(again?.required, isTrue);
    });

    test('an optional update is not repeated inside the 6-hour wait', () async {
      SharedPreferences.setMockInitialValues({});
      final client = MockClient((r) async => http.Response.bytes(utf8.encode(jsonEncode(release('v99.0.0', required: false))), 200));
      expect(await UpdateService(client: client).check(), isNotNull);
      expect(await UpdateService(client: client).check(), isNull);
    });
  });

  test('profile pictures: any one emoji, not letters or digits', () {
    for (final e in ['😊', '🎧', '👍🏽', '🇮🇳', '👨‍👩‍👧', '❤️']) {
      expect(isEmoji(e), isTrue, reason: e);
    }
    for (final e in ['', 'a', 'ab', '7', '😊😊', '#', ' ']) {
      expect(isEmoji(e), isFalse, reason: e);
    }
  });

  group('your choices', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('moods and singers save on the profile; new singers tune suggestions', () async {
      final lib = await LibraryStore.load();
      lib.signIn(const Profile(name: 'Asha', email: 'a@b.co', createdAt: 1));
      lib.updateChoices(moods: ['chill'], artists: ['Arijit Singh']);
      expect(lib.profile!.moods, ['chill']);
      expect(lib.profile!.artists, ['Arijit Singh']);
      expect(lib.taste.topArtists(n: 3).map((a) => a.name), contains('Arijit Singh'));
      lib.setLanguages(['bengali']);
      expect(lib.profile!.languages, ['bengali']);
    });

    test('guests have no profile to change', () async {
      final lib = await LibraryStore.load();
      lib.updateChoices(moods: ['chill']);
      expect(lib.profile, isNull);
    });
  });
}
