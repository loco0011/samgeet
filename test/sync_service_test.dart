import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behaves like backend/api/backup.php, in memory.
class FakeServer {
  final rows = <String, ({String data, int rev, String? email})>{};

  MockClient get client => MockClient((req) async {
        final key = req.headers['X-Restore-Code'] ?? '';
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        switch (b['action']) {
          case 'check_email':
            return http.Response(jsonEncode({'exists': rows.values.any((r) => r.email == b['email_hash'])}), 200);
          case 'load':
            final r = rows[key];
            return r == null ? http.Response('{"error":"not_found"}', 404) : http.Response(jsonEncode({'data': r.data, 'rev': r.rev}), 200);
          case 'delete':
            rows.remove(key);
            return http.Response('{"ok":true}', 200);
          case 'save':
            final base = b['base_rev'] as int?;
            final cur = rows[key];
            if ((base == null && cur != null) || (base != null && cur?.rev != base)) return http.Response('{"error":"conflict"}', 409);
            final rev = (cur?.rev ?? 0) + 1;
            rows[key] = (data: b['data'] as String, rev: rev, email: (b['email_hash'] as String?) ?? cur?.email);
            return http.Response(jsonEncode({'ok': true, 'rev': rev}), 200);
        }
        return http.Response('{"error":"bad_action"}', 400);
      });
}

/// A phone: its own storage, talking to the shared server. SharedPreferences is one global in
/// tests, so each phone keeps its storage here and swaps it in while it works.
class Phone {
  final FakeServer server;
  Map<String, Object> storage;
  Phone(this.server, [Map<String, Object>? start]) : storage = {...?start};

  Future<T> use<T>(Future<T> Function(SyncService s, SharedPreferences p) f) async {
    SharedPreferences.setMockInitialValues(storage);
    final p = await SharedPreferences.getInstance();
    await p.reload();
    final s = SyncService(p, client: server.client);
    final out = await f(s, p);
    storage = {for (final k in p.getKeys()) k: p.get(k)!};
    return out;
  }

  List<String> ids(String key) => (jsonDecode(storage[key] as String? ?? '[]') as List).map((m) => '${m['id']}').toList();
}

String songs(List<String> ids) => jsonEncode([for (final i in ids) {'id': i, 'title': 'Song $i'}]);

const email = 'me@example.com', password = 'correct horse';

Future<AccountCheck> signIn(Phone phone, {String pw = password}) => phone.use((s, _) async {
      final c = await s.check(email, pw);
      if (c.state == AccountState.existing || c.state == AccountState.fresh) await s.join(c);
      return c;
    });

void main() {
  group('keys', () {
    test('the same on every phone, salted by email', () {
      final k = SyncService.keyFor('Me@Example.com ', password);
      expect(k, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{12}$')));
      expect(SyncService.keyFor(email, password), k);
      expect(SyncService.keyFor('you@example.com', password), isNot(k));
      expect(SyncService.keyFor(email, 'Correct horse'), isNot(k));
    });
  });

  group('merge', () {
    test('both phones add songs: all kept, this phone\'s first', () {
      final base = {'favorites': songs(['a'])};
      final mine = {'favorites': songs(['m', 'a'])};
      final theirs = {'favorites': songs(['t', 'a'])};
      expect(SyncService.merge(base, mine, theirs)['favorites'], songs(['m', 't', 'a']));
    });

    test('a song removed on either phone stays removed', () {
      final base = {'favorites': songs(['a', 'b', 'c'])};
      final mine = {'favorites': songs(['b', 'c'])}; // removed a
      final theirs = {'favorites': songs(['a', 'b'])}; // removed c
      expect(SyncService.merge(base, mine, theirs)['favorites'], songs(['b']));
    });

    test('settings changed on one side move over; on both sides the server wins', () {
      final base = <String, Object>{'quality': 320, 'autoplay': true};
      final mine = <String, Object>{'quality': 96, 'autoplay': false};
      final theirs = <String, Object>{'quality': 320, 'autoplay': true, 'accent': 'midnight'};
      expect(SyncService.merge(base, mine, theirs), {'quality': 96, 'autoplay': false, 'accent': 'midnight'});
      expect(SyncService.merge(base, {'quality': 96}, {'quality': 160})['quality'], 160);
    });

    test('history is capped', () {
      final mine = {'history': songs([for (var i = 0; i < 100; i++) 'm$i'])};
      final theirs = {'history': songs([for (var i = 0; i < 100; i++) 't$i'])};
      expect((jsonDecode(SyncService.merge({}, mine, theirs)['history'] as String) as List).length, 150);
    });
  });

  test('sign in: new account keeps this phone\'s library; a second phone gets it all', () async {
    final server = FakeServer();
    final a = Phone(server, {'favorites': songs(['a1', 'a2']), 'profile': '{"name":"Sam"}', 'quality': 160});
    expect((await signIn(a)).state, AccountState.fresh);
    expect(server.rows, hasLength(1));

    final b = Phone(server); // a fresh install
    expect((await signIn(b)).state, AccountState.existing);
    expect(b.ids('favorites'), ['a1', 'a2']);
    expect(b.storage['profile'], '{"name":"Sam"}');
    expect(b.storage['quality'], 160);
  });

  test('wrong password for an existing email is refused, not made into a new account', () async {
    final server = FakeServer();
    await signIn(Phone(server, {'favorites': songs(['a'])}));
    final b = Phone(server);
    expect((await signIn(b, pw: 'wrong password')).state, AccountState.wrongPassword);
    expect(server.rows, hasLength(1));
    expect(await b.use((s, _) async => s.loggedIn), isFalse);
  });

  test('two phones in use: changes from both end up on both', () async {
    final server = FakeServer();
    final a = Phone(server, {'favorites': songs(['x'])});
    await signIn(a);
    final b = Phone(server, {'favorites': songs(['guest'])}); // liked something as a guest first
    await signIn(b);
    expect(b.ids('favorites'), containsAll(['x', 'guest']));

    // Both change things without seeing each other.
    await a.use((s, p) async {
      await p.setString('favorites', songs(['fromA', ...a.ids('favorites')]));
      await p.setString('playlists', jsonEncode([{'id': 'p1', 'name': 'Road trip', 'tracks': []}]));
    });
    b.storage['favorites'] = songs(['fromB', ...b.ids('favorites')..remove('x')]); // B also unliked x

    await a.use((s, _) => s.sync());
    await b.use((s, _) => s.sync()); // B raced A: merges instead of overwriting
    await a.use((s, _) => s.sync());

    for (final p in [a, b]) {
      expect(p.ids('favorites').toSet(), {'fromA', 'fromB', 'guest'});
      expect(p.storage['playlists'], contains('Road trip'));
    }
  });

  test('signing out stops syncing but keeps the account', () async {
    final server = FakeServer();
    final a = Phone(server, {'favorites': songs(['a'])});
    await signIn(a);
    await a.use((s, _) => s.logOut());
    expect(await a.use((s, _) async => s.loggedIn), isFalse);
    expect(server.rows, hasLength(1));
    expect((await signIn(Phone(server))).state, AccountState.existing);
  });

  test('offline: sign-in says so and changes nothing', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SyncService(await SharedPreferences.getInstance(), client: MockClient((_) async => throw Exception('no network')));
    expect((await s.check(email, password)).state, AccountState.offline);
    expect(s.loggedIn, isFalse);
  });
}
