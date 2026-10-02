import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'profile.dart';

/// Keeps the account's profile (name, picture choice, favourite languages, moods and singers, and
/// the player look) up to date on Samgeet's server (`backend/samgeet/api/auth.php`), so reports can
/// group listeners by taste. The library itself syncs through `SyncService`.
///
/// Only sent while signed in to an account. Failures are silent: the app works offline, and the
/// change is retried the next time the app starts.
class CloudService {
  /// The public site: share pages and short links (`/s/<code>`) live here.
  static const baseUrl = 'https://api.sambitmaity.fun';
  static const _savePending = 'cloudSavePending';

  final SharedPreferences _prefs;
  final ApiClient api;

  CloudService(this._prefs, this.api);

  Map<String, dynamic> payload(Profile p, {String? playerStyle}) => {
        'action': 'profile',
        'name': p.name,
        'avatar': p.photoPath != null ? '' : p.avatar, // a photo never leaves the phone
        'languages': p.languages,
        'moods': p.moods,
        'artists': p.artists,
        'player_style': ?playerStyle,
      };

  /// Uploads the profile. If it can't be sent now it is retried on the next start.
  Future<void> saveProfile(Profile p, {String? playerStyle}) async {
    if (!api.hasSession) {
      await _prefs.setBool(_savePending, true);
      return;
    }
    final r = await api.post('auth', payload(p, playerStyle: playerStyle), timeout: const Duration(seconds: 10));
    await _prefs.setBool(_savePending, r?.ok != true);
  }

  /// Signing out keeps the account and its profile on the server; nothing to send.
  Future<void> deleteProfile() => _prefs.setBool(_savePending, false);

  /// Call once at startup: finishes whatever the last session couldn't send.
  Future<void> retryPending(Profile? current, {String? playerStyle}) async {
    if ((_prefs.getBool(_savePending) ?? false) && current != null) await saveProfile(current, playerStyle: playerStyle);
  }
}
