import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/admin_service.dart';
import 'package:samgeet/data/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final future = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;

  Future<(AdminService, List<http.Request>)> make(http.Response Function(Map<String, dynamic> body, http.Request r) answer) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final sent = <http.Request>[];
    final api = ApiClient(
      prefs,
      base: 'https://x.test/api',
      appKey: 'k' * 32,
      deviceInfo: () async => {},
      client: MockClient((r) async {
        sent.add(r);
        return answer(jsonDecode(r.body) as Map<String, dynamic>, r);
      }),
    );
    return (AdminService(prefs, api), sent);
  }

  test('signing in keeps a pass that later calls send', () async {
    final (admin, sent) = await make(
      (b, r) => b['action'] == 'login'
          ? http.Response(jsonEncode({'token': '1.$future.${'a' * 64}', 'expires': future}), 200)
          : http.Response(jsonEncode({'notifications': []}), 200),
    );
    expect(admin.signedIn, isFalse);
    expect(await admin.signIn(' Me@Example.com ', 'pw'), isNull);
    expect(admin.signedIn, isTrue);
    expect(jsonDecode(sent.first.body)['email'], 'me@example.com');
    await admin.history();
    expect(sent.last.headers['X-Samgeet-Admin'], '1.$future.${'a' * 64}');
  });

  test('a wrong password or a lockout says so in words', () async {
    var status = 403;
    final (admin, _) = await make((b, r) => http.Response('{"error":"x"}', status));
    expect(await admin.signIn('a@b.co', 'x'), 'Wrong email or password.');
    status = 429;
    expect(await admin.signIn('a@b.co', 'x'), contains('15 minutes'));
  });

  test('an expired or cancelled pass signs this phone out of admin', () async {
    var login = true;
    final (admin, _) = await make((b, r) {
      if (login) return http.Response(jsonEncode({'token': 't', 'expires': future}), 200);
      return http.Response('{"error":"admin_session"}', 401);
    });
    await admin.signIn('a@b.co', 'pw');
    login = false;
    expect(await admin.history(), isNull);
    expect(admin.signedIn, isFalse);
  });

  test('the message button goes as "button", so it never replaces the call', () async {
    final (admin, sent) = await make((b, r) => http.Response('{"ok":true,"id":5}', 200));
    final m = SentMessage(id: 3, title: 'Hi', body: 'There', action: 'search', actionValue: 'arijit', sentAt: DateTime(2026));
    expect(await admin.send(m.toDraft()), isNull);
    final body = jsonDecode(sent.single.body) as Map;
    expect(body['action'], 'send');
    expect(body['button'], 'search');
    expect(body['action_value'], 'arijit');
  });

  test('history reads messages and their numbers', () async {
    final (admin, _) = await make(
      (b, r) => http.Response(
        jsonEncode({
          'notifications': [
            {
              'id': 9,
              'title': 'T',
              'body': 'B',
              'style': 'celebrate',
              'action': 'none',
              'show_as': 'both',
              'audience': 'all',
              'active': true,
              'sent_at': 1790000000,
              'delivered': 40,
              'opened': 13,
              'dismissed': 2,
            },
            {'title': 'broken, no id'},
          ],
        }),
        200,
      ),
    );
    final list = (await admin.history())!.items;
    expect(list, hasLength(1));
    expect((list.single.delivered, list.single.opened, list.single.style), (40, 13, 'celebrate'));
  });

  test('reports read forgivingly: missing or odd values give defaults instead of errors', () {
    const j = J({
      'n': 3,
      'f': 2.6,
      's': '12',
      'pair': [5, 4],
      'one': [7],
      'at': '2026-10-03 10:00:00',
      'kids': [
        {'a': 1},
        'skip',
      ],
    });
    expect((j.i('n'), j.i('f'), j.i('s'), j.i('missing')), (3, 3, 12, 0));
    expect((j.s('n'), j.s('missing'), j.b('n')), ('3', '', false));
    expect(j.pair('pair'), (5, 4));
    expect(j.pair('one'), (7, null));
    expect(j.list('kids').single.i('a'), 1);
    expect(j.time('at')!.toUtc(), DateTime.utc(2026, 10, 3, 10));
    expect(j.o('missing').raw, isEmpty);
  });

  test('re-sending names who it goes to, and explains a missing server update', () async {
    final (admin, sent) = await make(
      (b, r) => b['who'] == 'missed' ? http.Response(jsonEncode({'error': 'needs_update'}), 422) : http.Response(jsonEncode({'ok': true, 'id': 12}), 200),
    );
    expect(await admin.resend(4, who: 'unopened'), isNull);
    expect(jsonDecode(sent.last.body), {'action': 'resend', 'id': 4, 'who': 'unopened'});
    expect(await admin.resend(4, who: 'missed'), contains('database update'));
  });

  test('the web panel sits next to the API folder', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(AdminService(prefs, ApiClient(prefs, base: 'https://x.test/abc/samgeet/api', appKey: 'k' * 32)).webPanel, 'https://x.test/abc/samgeet/admin/');
    expect(AdminService(prefs, ApiClient(prefs, base: '', appKey: '')).webPanel, isNull);
  });
}
