import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'track.dart';

/// What the app reports to Samgeet's server (`backend/samgeet/api/events.php`) so listening can be
/// analysed later: plays and how long each lasted, skips, likes, downloads, shares, searches,
/// playlists, settings, and how notifications and updates are received. Each event names the song
/// (with its singers and album), and the server links it to the phone and, when signed in, the account.
///
/// Events wait in a small queue on the phone (kept across restarts, capped) and go up in batches:
/// every minute, once 40 are waiting, and when the app goes to the background.
class Analytics {
  static const _queuePref = 'analyticsQueue';
  static const _maxQueued = 1000;
  static const _batch = 200;

  final SharedPreferences _prefs;
  final ApiClient api;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  bool _sending = false;
  AppLifecycleListener? _lifecycle;

  Analytics(this._prefs, this.api) {
    try {
      final saved = _prefs.getString(_queuePref);
      if (saved != null) _queue.addAll((jsonDecode(saved) as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
    } catch (_) {}
  }

  int get pending => _queue.length;

  /// The song as the server stores it.
  static Map<String, dynamic> trackJson(Track t) => {
        'id': t.id,
        'title': t.title,
        'album': t.album,
        'album_id': t.albumId,
        'lang': t.language,
        'year': t.year > 0 ? t.year : null,
        'dur': t.durationSec,
        'img': t.art(150),
        'artists': [for (final a in t.artists.take(8)) {'id': a.id, 'name': a.name}],
      };

  /// Records one event. [value] is a short text (a search, why a song ended, a setting), [ms] a
  /// duration, [meta] anything else small.
  void log(String type, {Track? track, int? ms, String? value, Map<String, Object?>? meta}) {
    _queue.add({
      't': type,
      'at': DateTime.now().millisecondsSinceEpoch,
      if (track != null && track.id.isNotEmpty) 'track': trackJson(track),
      'ms': ?ms,
      if (value != null && value.isNotEmpty) 'v': value.length > 250 ? value.substring(0, 250) : value,
      if (meta != null && meta.isNotEmpty) 'm': meta,
    });
    if (_queue.length > _maxQueued) _queue.removeRange(0, _queue.length - _maxQueued);
    _save();
    if (_queue.length >= 40) unawaited(flush());
  }

  void _save() {
    _prefs.setString(_queuePref, jsonEncode(_queue));
  }

  /// Sends what's waiting. Events stay queued if the server can't be reached.
  Future<void> flush() async {
    if (_sending || _queue.isEmpty || !api.configured) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(_batch).toList();
        final r = await api.post('events', {'events': batch});
        if (r == null || r.status == 429 || r.status >= 500) break; // try again later
        // Sent, or refused as malformed (dropping it stops one bad event blocking the rest).
        _queue.removeRange(0, batch.length);
        _save();
        if (r.status == 401) break;
      }
    } finally {
      _sending = false;
    }
  }

  /// Call once at startup.
  void start() {
    log('app_open');
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => flush());
    _lifecycle ??= AppLifecycleListener(
      onPause: () {
        log('app_close');
        flush();
      },
      onResume: () => log('app_open', value: 'resume'),
    );
    unawaited(flush());
  }

  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
  }
}
