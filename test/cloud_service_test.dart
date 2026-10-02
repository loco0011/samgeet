import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/analytics.dart';
import 'package:samgeet/data/api_client.dart';
import 'package:samgeet/data/app_config.dart';
import 'package:samgeet/data/cloud_service.dart';
import 'package:samgeet/data/profile.dart';
import 'package:samgeet/data/track.dart';
import 'package:samgeet/data/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const asha = Profile(name: 'Asha', email: 'a@b.co', languages: ['bengali'], artists: ['Kishore Kumar'], avatar: 'emoji:🎧', createdAt: 7);

  Future<(ApiClient, List<http.Request>, SharedPreferences)> make({
    int status = 200,
    bool offline = false,
    String body = '{}',
    String? session,
    String key = 'kkkkkkkkkkkkkkkkkkkkkkkkkkkkkkkk',
  }) async {
    SharedPreferences.setMockInitialValues({'apiSession': ?session});
    final prefs = await SharedPreferences.getInstance();
    final sent = <http.Request>[];
    final client = MockClient((r) async {
      sent.add(r);
      if (offline) throw http.ClientException('offline');
      return http.Response(body, status);
    });
    return (ApiClient(prefs, client: client, base: 'https://x.test/api', appKey: key, deviceInfo: () async => {'model': 'Test'}), sent, prefs);
  }

  group('ApiClient', () {
    test('signs requests exactly like the server checks them (lib/bootstrap.php)', () {
      // Worked out with PHP: hash_hmac('sha256', "auth\n1790000000\n<device>\n" . hash('sha256', '{"action":"me"}'), 'k' x 32)
      expect(ApiClient.sign('k' * 32, 'auth', '1790000000', 'ab' * 32, '{"action":"me"}'),
          'b45f6715aefe24ae25bed83fb09c53e4ed1d8b2dbe7bfb709dcce51c151aa24f');
    });

    test('sends the install id, time, signature and session', () async {
      final (api, sent, _) = await make(session: 's' * 43);
      final r = await api.post('auth', {'action': 'me'});
      expect(r!.ok, isTrue);
      final h = sent.single.headers;
      expect(sent.single.url.toString(), 'https://x.test/api/auth.php');
      expect(h['X-Samgeet-Device'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(h['X-Samgeet-Session'], 's' * 43);
      expect(h['X-Samgeet-Sign'], ApiClient.sign('k' * 32, 'auth', h['X-Samgeet-Time']!, h['X-Samgeet-Device']!, sent.single.body));
      await api.post('auth', {'action': 'me'});
      expect(sent.last.headers['X-Samgeet-Device'], h['X-Samgeet-Device'], reason: 'the install id stays the same');
    });

    test('switched off without an address and key: nothing is sent', () async {
      final (_, sent, prefs) = await make();
      expect(await ApiClient(prefs, base: '', appKey: '').post('auth', {}), isNull);
      expect(sent, isEmpty);
    });

    test('a phone with a wrong clock corrects itself and retries once', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
      var calls = 0;
      final api = ApiClient(prefs, base: 'https://x.test/api', appKey: 'k' * 32, deviceInfo: () async => {}, client: MockClient((r) async {
        calls++;
        final t = int.parse(r.headers['X-Samgeet-Time']!);
        if ((t - future).abs() > 300) return http.Response(jsonEncode({'error': 'clock', 'server_time': future}), 401);
        return http.Response('{"ok":true}', 200);
      }));
      expect((await api.post('app', {}))!.ok, isTrue);
      expect(calls, 2);
    });

    test('offline gives null', () async {
      final (api, _, _) = await make(offline: true);
      expect(await api.post('auth', {}), isNull);
    });
  });

  group('CloudService', () {
    test('sends the profile (never a photo path) to auth.php while signed in', () async {
      final (api, sent, prefs) = await make(session: 's' * 43);
      await CloudService(prefs, api).saveProfile(asha.copyWith(avatar: 'photo:/data/me.jpg'), playerStyle: 'cover');
      final body = jsonDecode(sent.single.body) as Map;
      expect(body['action'], 'profile');
      expect(body['name'], 'Asha');
      expect(body['avatar'], '');
      expect(body['player_style'], 'cover');
      expect(body['artists'], ['Kishore Kumar']);
    });

    test('not signed in yet, or offline: kept for the next start', () async {
      final (api, sent, prefs) = await make();
      final cloud = CloudService(prefs, api);
      await cloud.saveProfile(asha);
      expect(sent, isEmpty);
      await api.setSession('s' * 43);
      await cloud.retryPending(asha);
      expect(sent, hasLength(1));
      await cloud.retryPending(asha);
      expect(sent, hasLength(1), reason: 'nothing left to retry');
    });
  });

  group('Analytics', () {
    const song = Track(id: 's1', title: 'Kesariya', artists: [ArtistRef(id: 'a1', name: 'Arijit Singh')], album: 'Brahmastra', year: 2022, durationSec: 268);

    test('queues events with the song and sends them in a batch', () async {
      final (api, sent, prefs) = await make(body: '{"ok":true}');
      final a = Analytics(prefs, api);
      a.log('play_start', track: song, value: 'search');
      a.log('search', value: 'arijit');
      expect(a.pending, 2);
      await a.flush();
      expect(a.pending, 0);
      final events = (jsonDecode(sent.single.body) as Map)['events'] as List;
      expect(events.map((e) => e['t']), ['play_start', 'search']);
      expect(events.first['track'], containsPair('id', 's1'));
      expect((events.first['track'] as Map)['artists'], [{'id': 'a1', 'name': 'Arijit Singh'}]);
      expect(events.first['track'], containsPair('year', 2022));
    });

    test('kept across restarts when the server can\'t be reached', () async {
      final (api, _, prefs) = await make(offline: true);
      Analytics(prefs, api)
        ..log('like', track: song)
        ..log('download', track: song);
      await Analytics(prefs, api).flush();
      expect(Analytics(prefs, api).pending, 2);
    });
  });

  group('updates from the admin panel', () {
    test('a newer published build is offered; links stay on trusted hosts', () {
      final u = AppUpdate.fromServer({'version': '9.0.0', 'build': 999, 'notes': '- **Big.** Change', 'url': 'https://api.sambitmaity.fun/x/samgeet/files/Samgeet-9.0.0.apk', 'required': true, 'size': 5})!;
      expect(u.required, isTrue);
      expect(u.notes, '• Big. Change');
      expect(AppUpdate.fromServer({'version': '9.0.0', 'build': 1, 'url': 'https://github.com/loco0011/samgeet/releases/download/v9/Samgeet.apk'}), isNull);
      expect(AppUpdate.fromServer({'version': '9.0.0', 'build': 999, 'url': 'https://evil.example/Samgeet.apk'}), isNull);
      expect(AppUpdate.isTrustedLink('https://api.sambitmaity.fun/x/samgeet/admin/index.php'), isFalse);
    });

    test('messages: unknown fields are ignored and only https pictures kept', () {
      final a = Announcement.fromJson({'id': 3, 'title': 'Hi', 'body': 'b', 'image': 'http://x/y.png', 'action': 'update', 'show_as': 'popup'})!;
      expect(a.image, '');
      expect(a.buttonLabel, 'Update now');
      expect((a.popup, a.system), (true, false));
      expect(Announcement.fromJson({'title': 'no id'}), isNull);
    });
  });
}
