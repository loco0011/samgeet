import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/api_client.dart';
import 'package:samgeet/data/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behaves like backend/samgeet/api/auth.php + library.php, in memory.
class FakeServer {
  final rows = <String, ({String email, String? data, int rev})>{}; // account key -> account
  final sessions = <String, String>{}; // session token -> account key
  var _tokens = 0;

  http.Response _json(int code, Map<String, Object?> body) => http.Response(jsonEncode(body), code);

  String _session(String key) {
    final t = (++_tokens).toString().padLeft(43, 't');
    sessions[t] = key;
    return t;
  }

  MockClient get client => MockClient((req) async {
        expect(req.headers['X-Samgeet-Sign'], matches(RegExp(r'^[a-f0-9]{64}$')));
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        if (req.url.path.endsWith('/auth.php')) {
          final key = b['key'] as String?;
          switch (b['action']) {
            case 'login':
              if (rows.containsKey(key)) return _json(200, {'token': _session(key!), 'user': {}});
              if (rows.values.any((r) => r.email == b['email'])) return _json(403, {'error': 'wrong_password'});
              return _json(404, {'error': 'no_account'});
            case 'register':
              if (rows.values.any((r) => r.email == b['email'])) return _json(403, {'error': 'wrong_password'});
              rows[key!] = (email: b['email'] as String, data: null, rev: 0);
              return _json(200, {'token': _session(key), 'user': {}});
            case 'logout':
              sessions.remove(req.headers['X-Samgeet-Session']);
              return _json(200, {'ok': true});
          }
          return _json(400, {'error': 'bad_action'});
        }
        final key = sessions[req.headers['X-Samgeet-Session']];
        final cur = rows[key];
        if (key == null || cur == null) return _json(401, {'error': 'session'});
        switch (b['action']) {
          case 'load':
            return cur.data == null ? _json(404, {'error': 'not_found'}) : _json(200, {'data': cur.data, 'rev': cur.rev});
          case 'save':
            final base = b['base_rev'] as int?;
            if ((base == null && cur.data != null) || (base != null && cur.rev != base)) return _json(409, {'error': 'conflict'});
            rows[key] = (email: cur.email, data: b['data'] as String, rev: cur.rev + 1);
            return _json(200, {'ok': true, 'rev': cur.rev + 1});
        }
        return _json(400, {'error': 'bad_action'});
      });
}

ApiClient testApi(SharedPreferences p, http.Client client) =>
    ApiClient(p, client: client, base: 'https://x.test/api', appKey: 'k' * 32, deviceInfo: () async => {});

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
    final s = SyncService(p, api: testApi(p, server.client));
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
      if (c.state == AccountState.fresh) expect(await s.register(c, 'Sam'), isTrue);
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
    final p = await SharedPreferences.getInstance();
    final s = SyncService(p, api: testApi(p, MockClient((_) async => throw Exception('no network'))));
    expect((await s.check(email, password)).state, AccountState.offline);
    expect(s.loggedIn, isFalse);
  });

  test('an expired session signs in again by itself', () async {
    final server = FakeServer();
    final a = Phone(server, {'favorites': songs(['a'])});
    await signIn(a);
    server.sessions.clear(); // every session ran out (or was signed out from the admin panel)
    a.storage['favorites'] = songs(['b', 'a']);
    expect(await a.use((s, _) => s.sync()), isTrue);
    expect(server.sessions, hasLength(1));
    expect(await Phone(server).use((s, _) async => s.loggedIn), isFalse);
    final b = Phone(server);
    await signIn(b);
    expect(b.ids('favorites'), ['b', 'a']);
  });

  test('an account deleted elsewhere signs this phone out', () async {
    final server = FakeServer();
    final a = Phone(server, {'favorites': songs(['a'])});
    await signIn(a);
    server.rows.clear();
    server.sessions.clear();
    expect(await a.use((s, _) => s.sync()), isFalse);
    expect(await a.use((s, _) async => (s.loggedIn, s.status)), (false, SyncStatus.loggedOutElsewhere));
  });

  test('signing out ends the session on the server', () async {
    final server = FakeServer();
    final a = Phone(server);
    await signIn(a);
    expect(server.sessions, hasLength(1));
    await a.use((s, _) async {
      await s.logOut();
      await Future<void>.delayed(Duration.zero);
    });
    expect(server.sessions, isEmpty);
  });
}
