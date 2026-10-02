import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

/// An answer from Samgeet's server: the HTTP status and the JSON body (empty if it had none).
class ApiResponse {
  final int status;
  final Map<String, dynamic> json;
  const ApiResponse(this.status, this.json);
  bool get ok => status == 200;
  String? get error => json['error'] as String?;
}

/// Talks to Samgeet's own server (`backend/samgeet/api/`).
///
/// Every request is signed so the server only answers this app: an HMAC of the endpoint, the time,
/// this install's id and the body, with a key built into release builds (never in git). The
/// address and key come from `secrets.json` at build time:
/// `flutter build apk --release --dart-define-from-file=secrets.json`. Without them (tests, a plain
/// debug build) the client is switched off and every call returns null, like being offline.
///
/// Signed-in calls also carry the session token from `auth.php`, which tells the server whose
/// account it is.
class ApiClient {
  static const defaultBase = String.fromEnvironment('SAMGEET_API');
  static const _defaultKey = String.fromEnvironment('SAMGEET_APP_KEY');

  static const installPref = 'installKey'; // shared with CloudService from 1.3.x
  static const sessionPref = 'apiSession';
  static const _skewPref = 'apiClockSkew';

  final SharedPreferences _prefs;
  final http.Client _http;
  final String base;
  final String _appKey;

  /// Details about this phone and app, sent with sign-in and the start-up config call.
  Future<Map<String, Object?>> Function() deviceInfo;

  ApiClient(this._prefs, {http.Client? client, String? base, String? appKey, Future<Map<String, Object?>> Function()? deviceInfo})
      : _http = client ?? http.Client(),
        base = base ?? defaultBase,
        _appKey = appKey ?? _defaultKey,
        deviceInfo = deviceInfo ?? describeDevice;

  bool get configured => base.isNotEmpty && _appKey.length >= 32;

  /// This install's random id (64 hex), made on first use. Only its hash is kept on the server.
  String get installKey {
    var k = _prefs.getString(installPref);
    if (k == null || k.length != 64) {
      final r = Random.secure();
      k = List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _prefs.setString(installPref, k);
    }
    return k;
  }

  String? get session => _prefs.getString(sessionPref);
  bool get hasSession => session != null;
  Future<void> setSession(String? token) => token == null ? _prefs.remove(sessionPref) : _prefs.setString(sessionPref, token);

  static String sign(String key, String endpoint, String time, String device, String body) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode('$endpoint\n$time\n$device\n${sha256.convert(utf8.encode(body))}')).toString();

  /// POSTs [body] to `<endpoint>.php`. Null when offline, switched off, or the answer wasn't JSON.
  Future<ApiResponse?> post(String endpoint, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 20), Map<String, String> headers = const {}}) async {
    if (!configured) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      final text = jsonEncode(body);
      final time = '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + (_prefs.getInt(_skewPref) ?? 0)}';
      final device = installKey;
      final token = session;
      http.Response r;
      try {
        r = await _http
            .post(
              Uri.parse('$base/$endpoint.php'),
              headers: {
                'Content-Type': 'application/json',
                'X-Samgeet-Device': device,
                'X-Samgeet-Time': time,
                'X-Samgeet-Sign': sign(_appKey, endpoint, time, device, text),
                'X-Samgeet-Session': ?token,
                ...headers,
              },
              body: text,
            )
            .timeout(timeout);
      } catch (_) {
        return null;
      }
      Map<String, dynamic> json;
      try {
        json = r.body.isEmpty ? const {} : Map<String, dynamic>.from(jsonDecode(r.body) as Map);
      } catch (_) {
        return null;
      }
      // The phone's clock is off: remember by how much and try once more.
      if (r.statusCode == 401 && json['error'] == 'clock' && json['server_time'] is int && attempt == 0) {
        await _prefs.setInt(_skewPref, (json['server_time'] as int) - DateTime.now().millisecondsSinceEpoch ~/ 1000);
        continue;
      }
      return ApiResponse(r.statusCode, json);
    }
    return null;
  }

  /// Model, Android version, app version, language and time zone.
  static Future<Map<String, Object?>> describeDevice() async {
    final out = <String, Object?>{
      'app_version': kVersionName,
      'app_build': kBuildNumber,
      'locale': Platform.localeName,
      'tz': DateTime.now().timeZoneName,
    };
    if (Platform.isAndroid) {
      try {
        final a = await DeviceInfoPlugin().androidInfo;
        out.addAll({'brand': a.brand, 'model': a.model, 'os': a.version.release, 'sdk': a.version.sdkInt});
      } catch (_) {}
    }
    return out;
  }
}
