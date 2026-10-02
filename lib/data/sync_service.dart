import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';


/// Where syncing stands, for the UI.
enum SyncStatus { off, syncing, synced, offline, loggedOutElsewhere }

/// Keeps everything the app saves on the phone (playlists, favourites, history, taste, profile,
/// settings, equalizer) the same on every phone logged in to the same account, through Samgeet's
/// server (see `backend/samgeet/api/library.php`).
///
/// An account is an email + password. The phone turns them into a 12-character key (PBKDF2, salted
/// with the email); the password never leaves the phone and the server stores only a hash of the key.
/// Signing in with the key gives a session token ([ApiClient.session]) that every library call
/// carries; when it runs out the phone signs in again with the saved key.
///
/// Syncing is a three-way merge: the phone remembers the copy it last agreed on with the server
/// (the "base"), so it can tell what changed here, what changed on another phone, and combine both.
/// Lists of songs, playlists and artists merge item by item, deletions included; for anything else
/// changed on both sides, the server's copy wins. Saves name the revision they built on, so a phone
/// that raced another one merges again instead of overwriting it.
class SyncService extends ChangeNotifier {
  static const _keyPref = 'syncKey';
  static const _emailPref = 'syncEmail';
  static const _basePref = 'syncBase';
  static const _revPref = 'syncRev';
  static const _lastPref = 'syncLastAt';
  static const _pendingPref = 'syncPending';
  static const _elsewherePref = 'syncLoggedOutElsewhere';

  /// The app version the "sign in / add a password" popup was last shown for (this phone only).
  static const nudgePref = 'signInNudgeShown';

  /// Bookkeeping that belongs to this phone, never synced.
  static const _local = {
    _keyPref, _emailPref, _basePref, _revPref, _lastPref, _pendingPref, _elsewherePref, //
    'installKey', 'cloudSavePending', 'cloudDeletePending', 'themeMood', nudgePref, //
    ApiClient.sessionPref, 'apiClockSkew', 'analyticsQueue', 'notifSeen', 'update_skip_version', 'update_last_check',
    'dl.index', 'dl.quality', // downloads are files on this phone
    'dailyMix', // rebuilt on each phone every day
  };

  /// Lists of JSON objects that merge item by item, newest first, with an optional cap.
  static const _idLists = {'favorites': null, 'playlists': null, 'history': 150, 'artists': null};

  /// String lists that merge value by value.
  static const _valueLists = {'searches': 12};

  static const minPasswordLength = 8;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'; // Crockford base32
  static const _rounds = 150000; // PBKDF2: slow enough that a stolen table can't be tried quickly

  final SharedPreferences _prefs;
  final ApiClient api;

  /// Writes anything still waiting to be saved, so a sync sees the latest. Set by the app.
  Future<void> Function()? beforeSnapshot;

  /// Called after changes from another phone were written into storage, to reload what's in memory.
  Future<void> Function()? onRemoteApplied;

  Timer? _timer;
  bool _syncing = false;
  bool _again = false;
  DateTime _lastResumeSync = DateTime(0);
  AppLifecycleListener? _lifecycle;

  SyncService(this._prefs, {ApiClient? api}) : api = api ?? ApiClient(_prefs);

  // ---------- state ----------
  bool get loggedIn => _prefs.getString(_keyPref) != null;
  String? get email => _prefs.getString(_emailPref);
  DateTime? get lastSync {
    final ms = _prefs.getInt(_lastPref);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  SyncStatus get status {
    if (_prefs.getBool(_elsewherePref) ?? false) return SyncStatus.loggedOutElsewhere;
    if (!loggedIn) return SyncStatus.off;
    if (_syncing) return SyncStatus.syncing;
    if (_prefs.getBool(_pendingPref) ?? false) return SyncStatus.offline;
    return SyncStatus.synced;
  }

  // ---------- keys ----------
  static String _cleanEmail(String e) => e.trim().toLowerCase();

  /// Email + password -> account key, the same on every phone. PBKDF2-HMAC-SHA256 salted with the
  /// email, so equal passwords still give different accounts. The first 60 bits become the key.
  static String keyFor(String email, String password) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([...utf8.encode('samgeet-backup:${_cleanEmail(email)}'), 0, 0, 0, 1]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < _rounds; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    final out = StringBuffer();
    var acc = 0, bits = 0;
    for (final b in t) {
      acc = (acc << 8) | b;
      bits += 8;
      while (bits >= 5 && out.length < 12) {
        bits -= 5;
        out.write(_alphabet[(acc >> bits) & 31]);
      }
      acc &= (1 << bits) - 1;
      if (out.length == 12) break;
    }
    return out.toString();
  }

  static Future<String> _derive(String email, String password) =>
      compute((List<String> a) => keyFor(a[0], a[1]), [email, password]);

  // ---------- server ----------
  /// The account isn't there any more (password changed elsewhere, or the account was deleted).
  static const _gone = ApiResponse(410, {'error': 'gone'});

  Future<ApiResponse?> _login(String email, String key) async =>
      api.post('auth', {'action': 'login', 'email': _cleanEmail(email), 'key': key, 'device': await api.deviceInfo()});

  /// A library call, signing in first (again) when there's no session or it ran out.
  Future<ApiResponse?> _library(Map<String, dynamic> body) async {
    final key = _prefs.getString(_keyPref), mail = email;
    if (key == null || mail == null) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!api.hasSession) {
        final r = await _login(mail, key);
        if (r == null) return null;
        // Only these answers mean the account is gone; any other 404 (e.g. a misconfigured server
        // refusing the signature) must not sign everyone out.
        if (const {'no_account', 'wrong_password', 'blocked'}.contains(r.error)) return _gone;
        if (!r.ok || r.json['token'] is! String) return r;
        await api.setSession(r.json['token'] as String);
      }
      final r = await api.post('library', body);
      if (r?.status != 401) return r;
      await api.setSession(null); // expired, or signed out from the admin panel: sign in again
    }
    return null;
  }

  static String _pack(Map<String, Object> prefs) => base64Encode(gzip.encode(utf8.encode(jsonEncode({'v': 1, 'prefs': prefs}))));

  static Map<String, Object> _unpack(String data) {
    final j = jsonDecode(utf8.decode(gzip.decode(base64Decode(data)))) as Map<String, dynamic>;
    return {for (final e in (j['prefs'] as Map).entries) '${e.key}': e.value as Object};
  }

  // ---------- storage ----------
  Map<String, Object> _snapshot() => {
        for (final k in _prefs.getKeys())
          if (!_local.contains(k) && _prefs.get(k) != null) k: _prefs.get(k)!,
      };

  Map<String, Object> _readBase() {
    final s = _prefs.getString(_basePref);
    if (s == null) return {};
    try {
      return {for (final e in (jsonDecode(s) as Map).entries) '${e.key}': e.value as Object};
    } catch (_) {
      return {};
    }
  }

  int? get _rev => _prefs.getInt(_revPref);

  Future<void> _agreed(Map<String, Object> copy, int rev) async {
    await _prefs.setString(_basePref, jsonEncode(copy));
    await _prefs.setInt(_revPref, rev);
    await _prefs.setInt(_lastPref, DateTime.now().millisecondsSinceEpoch);
    await _prefs.setBool(_pendingPref, false);
  }

  Future<void> _write(Map<String, Object> copy) async {
    for (final k in _prefs.getKeys().toList()) {
      if (!_local.contains(k) && !copy.containsKey(k)) await _prefs.remove(k);
    }
    for (final e in copy.entries) {
      if (_local.contains(e.key)) continue;
      final v = e.value;
      if (v is String) {
        await _prefs.setString(e.key, v);
      } else if (v is bool) {
        await _prefs.setBool(e.key, v);
      } else if (v is int) {
        await _prefs.setInt(e.key, v);
      } else if (v is double) {
        await _prefs.setDouble(e.key, v);
      } else if (v is List) {
        await _prefs.setStringList(e.key, [for (final s in v) '$s']);
      }
    }
  }

  // ---------- merging ----------
  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) return listEquals(a, b);
    return a == b;
  }

  static bool sameCopy(Map<String, Object> a, Map<String, Object> b) =>
      a.length == b.length && a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));

  static List<Map<String, dynamic>> _items(Object? json) {
    if (json is! String) return const [];
    try {
      return (jsonDecode(json) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return const [];
    }
  }

  static String _id(Map<String, dynamic> m) {
    final id = '${m['id'] ?? ''}';
    return id.isNotEmpty ? id : 'name:${m['name'] ?? ''}';
  }

  /// Three-way merge of a list: items added on either side are kept (this phone's first), items
  /// removed on either side stay removed, and an item edited here keeps this phone's version.
  static List<T> _mergeList<T>(List<T> base, List<T> mine, List<T> theirs, String Function(T) id, bool Function(T, T) same, int? cap) {
    final b = {for (final x in base) id(x): x};
    final m = {for (final x in mine) id(x): x};
    final t = {for (final x in theirs) id(x): x};
    final out = <T>[
      for (final x in mine)
        if (!b.containsKey(id(x)) && !t.containsKey(id(x))) x, // new here
      for (final x in theirs)
        if (!(b.containsKey(id(x)) && !m.containsKey(id(x)))) // not deleted here
          (m.containsKey(id(x)) && b.containsKey(id(x)) && !same(m[id(x)] as T, b[id(x)] as T)) ? m[id(x)] as T : x,
    ];
    return cap != null && out.length > cap ? out.sublist(0, cap) : out;
  }

  static bool _sameItem(Map<String, dynamic> a, Map<String, dynamic> b) => jsonEncode(a) == jsonEncode(b);

  /// Combines this phone's copy ([mine]) with the server's ([theirs]), given the copy both started from.
  static Map<String, Object> merge(Map<String, Object> base, Map<String, Object> mine, Map<String, Object> theirs) {
    final out = <String, Object>{};
    for (final k in {...base.keys, ...mine.keys, ...theirs.keys}) {
      final b = base[k], m = mine[k], t = theirs[k];
      Object? v;
      if (_same(m, t) || _same(t, b)) {
        v = m; // same on both, or only changed here
      } else if (_same(m, b)) {
        v = t; // only changed on the other phone
      } else if (_idLists.containsKey(k)) {
        v = jsonEncode(_mergeList(_items(b), _items(m), _items(t), _id, _sameItem, _idLists[k]));
      } else if (_valueLists.containsKey(k) && m is List && t is List) {
        String id(String s) => s;
        bool eq(String a, String b) => a == b;
        v = _mergeList(b is List ? [for (final s in b) '$s'] : <String>[], [for (final s in m) '$s'], [for (final s in t) '$s'], id, eq, _valueLists[k]);
      } else {
        v = t; // changed on both: the server's copy wins
      }
      if (v != null) out[k] = v;
    }
    return out;
  }

  // ---------- syncing ----------
  /// Syncs a little after the last change, so a burst of edits is one upload.
  void schedule() {
    if (!loggedIn) return;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 8), sync);
  }

  /// Syncs when the app comes back to the front, and pushes waiting changes when it goes to the back.
  void watchLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        if (DateTime.now().difference(_lastResumeSync) < const Duration(minutes: 1)) return;
        _lastResumeSync = DateTime.now();
        sync();
      },
      onPause: () {
        if (_timer?.isActive ?? false) sync();
      },
    );
  }

  /// Brings this phone and the server to the same library. Returns whether it got through.
  Future<bool> sync() async {
    _timer?.cancel();
    final key = _prefs.getString(_keyPref);
    if (key == null) return false;
    if (_syncing) {
      _again = true;
      return false;
    }
    _syncing = true;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        await beforeSnapshot?.call();
        final mine = _snapshot();
        final base = _readBase();
        final rev = _rev;

        final r = await _library({'action': 'load'});
        Map<String, Object>? theirs;
        int? theirRev;
        if (r?.status == 410) {
          await _logOutHere(elsewhere: true);
          return false;
        }
        if (r?.status == 200) {
          try {
            final body = r!.json;
            theirs = _unpack(body['data'] as String);
            theirRev = (body['rev'] as num).toInt();
          } catch (_) {
            return _failed();
          }
        } else if (r?.status == 404 && r?.error == 'not_found') {
          // The account has no library yet (a password change or a deleted account shows up as
          // the 410 above, when signing in again fails).
        } else {
          return _failed();
        }

        Map<String, Object> target;
        if (theirs == null || theirRev == rev) {
          target = mine;
          if (theirs != null && sameCopy(mine, base)) {
            await _agreed(mine, theirRev!);
            return true; // nothing new anywhere
          }
        } else {
          target = merge(base, mine, theirs);
          if (!sameCopy(target, mine)) {
            // Something changed here while we were loading: start over so it isn't lost.
            await beforeSnapshot?.call();
            if (!sameCopy(_snapshot(), mine)) continue;
            await _write(target);
            await onRemoteApplied?.call();
          }
          if (sameCopy(target, theirs)) {
            await _agreed(target, theirRev!);
            return true;
          }
        }

        final s = await _library({'action': 'save', 'data': _pack(target), 'base_rev': theirRev});
        if (s?.status == 200) {
          await _agreed(target, (s!.json['rev'] as num).toInt());
          return true;
        }
        if (s?.status != 409) return _failed();
        // Another phone saved in between: go round again and merge with that.
      }
      return _failed();
    } catch (_) {
      return _failed(); // an answer we didn't expect: try again later
    } finally {
      _syncing = false;
      notifyListeners();
      if (_again) {
        _again = false;
        schedule();
      }
    }
  }

  Future<bool> _failed() async {
    await _prefs.setBool(_pendingPref, true);
    return false;
  }

  // ---------- account ----------
  /// What signing in with [email] + [password] would do. An existing account is signed in to
  /// straight away (the session is kept in the result); pass the result to [join]. A new one needs
  /// [register] first.
  Future<AccountCheck> check(String email, String password) async {
    final key = await _derive(email, password);
    final r = await _login(email, key);
    if (r == null) return AccountCheck(api.configured ? AccountState.offline : AccountState.broken);
    if (r.status == 429) return AccountCheck(AccountState.slowDown);
    if (r.status == 200 && r.json['token'] is String) {
      return AccountCheck(AccountState.existing, key: key, email: email, token: r.json['token'] as String);
    }
    if (r.status == 404 && r.error == 'no_account') return AccountCheck(AccountState.fresh, key: key, email: email);
    if (r.error == 'wrong_password') return AccountCheck(AccountState.wrongPassword);
    if (r.error == 'blocked') return AccountCheck(AccountState.blocked);
    return AccountCheck(AccountState.broken);
  }

  /// Makes the new account [c] (from [check]) on the server, named [name]. Returns false if the
  /// server couldn't be reached or refused; [c] then has no session and [join] won't start.
  Future<bool> register(AccountCheck c, String name) async {
    if (c.state != AccountState.fresh || c.key == null || c.email == null) return false;
    final r = await api.post('auth', {'action': 'register', 'email': _cleanEmail(c.email!), 'key': c.key, 'name': name, 'device': await api.deviceInfo()});
    if (r?.status != 200 || r!.json['token'] is! String) return false;
    c.token = r.json['token'] as String;
    return true;
  }

  /// Starts syncing with a signed-in account. An existing account's library is merged into this
  /// phone (its profile and settings win); a new one starts from what's on this phone.
  Future<bool> join(AccountCheck c) async {
    if (!await adopt(c)) return false;
    return sync();
  }

  /// Signs this phone in to [c] without syncing yet (call [sync] next), so the app counts as
  /// signed in straight away.
  Future<bool> adopt(AccountCheck c) async {
    if (c.key == null || c.email == null || c.token == null) return false;
    await api.setSession(c.token);
    await _prefs.setString(_keyPref, c.key!);
    await _prefs.setString(_emailPref, _cleanEmail(c.email!));
    await _prefs.remove(_basePref); // nothing agreed yet: the first sync combines both sides
    await _prefs.remove(_revPref);
    await _prefs.remove(_elsewherePref);
    notifyListeners();
    return true;
  }

  /// Removes the account and everything the server keeps for it (library, listening history,
  /// sessions), then signs out here. False if the server couldn't be reached.
  Future<bool> deleteAccount() async {
    if (!api.hasSession) await _library({'action': 'load'}); // signs in again if needed
    final r = await api.post('auth', {'action': 'delete_account'});
    if (r?.status != 200) return false;
    await logOut();
    return true;
  }

  Future<void> _logOutHere({bool elsewhere = false}) async {
    _timer?.cancel();
    await api.setSession(null);
    for (final k in [_keyPref, _emailPref, _basePref, _revPref, _lastPref, _pendingPref]) {
      await _prefs.remove(k);
    }
    if (elsewhere) await _prefs.setBool(_elsewherePref, true);
    notifyListeners();
  }

  /// Stops syncing on this phone. The account and its library stay on the server.
  Future<void> logOut() async {
    _timer?.cancel();
    if (api.hasSession) unawaited(api.post('auth', {'action': 'logout'}, timeout: const Duration(seconds: 6)));
    await _prefs.remove(_elsewherePref);
    await _logOutHere();
  }

  /// Call once at startup.
  Future<void> start() async {
    watchLifecycle();
    if (loggedIn) await sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

enum AccountState { existing, fresh, wrongPassword, blocked, slowDown, offline, broken }

/// The answer from [SyncService.check].
class AccountCheck {
  final AccountState state;
  final String? key;
  final String? email;

  /// The session, once signed in (existing accounts) or registered ([SyncService.register]).
  String? token;
  AccountCheck(this.state, {this.key, this.email, this.token});
}
