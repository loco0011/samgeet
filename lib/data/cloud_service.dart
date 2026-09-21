import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'profile.dart';

/// Keeps a copy of the listener's profile on Samgeet's own server (see `backend/`).
///
/// Only the profile goes up; playlists, favourites, history and the uploaded photo stay on the phone.
/// Each install makes a random secret on first use and sends it with every request, so only that
/// install can change or delete its own row. Failures are silent: the app works offline, and the
/// change is retried the next time the app starts.
class CloudService {
  static const baseUrl = 'https://sambitmaity.fun/samgeet/api';
  static const _keyPref = 'installKey';
  static const _savePending = 'cloudSavePending';
  static const _deletePending = 'cloudDeletePending';

  final SharedPreferences _prefs;
  final http.Client _http;
  final String _base;

  CloudService(this._prefs, {http.Client? client, String? base})
      : _http = client ?? http.Client(),
        _base = base ?? baseUrl;

  String get _installKey {
    var k = _prefs.getString(_keyPref);
    if (k == null || k.length != 64) {
      final r = Random.secure();
      k = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _prefs.setString(_keyPref, k);
    }
    return k;
  }

  Map<String, dynamic> payload(Profile p) => {
        'action': 'save',
        'name': p.name,
        'email': p.email,
        'avatar': p.photoPath != null ? '' : p.avatar, // a photo never leaves the phone
        'languages': p.languages,
        'moods': p.moods,
        'artists': p.artists,
        'share_device_info': p.shareDeviceInfo,
        'device': p.shareDeviceInfo ? p.device?.toJson() : null,
        'created_at': p.createdAt,
      };

  Future<bool> _post(Map<String, dynamic> body) async {
    try {
      final r = await _http
          .post(
            Uri.parse('$_base/profile.php'),
            headers: {'Content-Type': 'application/json', 'X-Install-Key': _installKey},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Uploads the profile. If it can't be sent now it is retried on the next start.
  Future<void> saveProfile(Profile p) async {
    await _prefs.setBool(_deletePending, false);
    final ok = await _post(payload(p));
    await _prefs.setBool(_savePending, !ok);
  }

  /// Removes this install's profile from the server (used on sign-out).
  Future<void> deleteProfile() async {
    await _prefs.setBool(_savePending, false);
    final ok = await _post({'action': 'delete'});
    await _prefs.setBool(_deletePending, !ok);
  }

  /// Call once at startup: finishes whatever the last session couldn't send.
  Future<void> retryPending(Profile? current) async {
    if (_prefs.getBool(_deletePending) ?? false) {
      await deleteProfile();
    } else if ((_prefs.getBool(_savePending) ?? false) && current != null) {
      await saveProfile(current);
    }
  }
}
