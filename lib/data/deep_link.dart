import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'cloud_service.dart';
import 'share_service.dart';

/// What a tapped Samgeet share link points at.
sealed class SharedLink {
  const SharedLink();
}

class SharedSong extends SharedLink {
  final String id;
  final String title;
  const SharedSong(this.id, this.title);
}

class SharedPlaylist extends SharedLink {
  final String name;
  final List<String> ids;
  const SharedPlaylist(this.name, this.ids);
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Reads a share link (`https://api.sambitmaity.fun/share.php?...` or the `samgeet://share?...` form).
/// Links come from other people, so anything that isn't exactly ours, or is malformed, gives null.
SharedLink? parseSharedLink(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null) return null;
  final ours = (u.scheme == 'https' && u.host == Uri.parse(CloudService.baseUrl).host && u.path == '/share.php') ||
      (u.scheme == 'samgeet' && u.host == 'share');
  if (!ours) return null;

  final q = u.queryParameters;
  if (q['t'] == 'playlist') {
    final d = ShareService.decodePlaylist(raw);
    return d == null ? null : SharedPlaylist(d.name, d.ids);
  }
  final id = q['id'] ?? '';
  if (!_idPattern.hasMatch(id)) return null;
  final title = (q['s'] ?? '').trim();
  return SharedSong(id, title.length > 120 ? title.substring(0, 120) : title);
}

/// The code of a short share link in [text]: `https://api.sambitmaity.fun/s/<code>` (on its own or
/// inside a pasted message) or the page's `samgeet://share?c=<code>`. Null if there isn't one.
String? shortLinkCode(String text) {
  final host = RegExp.escape(Uri.parse(CloudService.baseUrl).host);
  final chars = ShareService.shortCodeChars;
  final m = RegExp('https://$host/s/([$chars]{7})(?![A-Za-z0-9])').firstMatch(text);
  if (m != null) return m.group(1);
  final u = Uri.tryParse(text.trim());
  if (u != null && u.scheme == 'samgeet' && u.host == 'share') {
    final c = u.queryParameters['c'] ?? '';
    if (ShareService.shortCodePattern.hasMatch(c)) return c;
  }
  return null;
}

/// Asks the server what the short link [code] stands for. Null if it's unknown or unreachable.
/// The answer is treated like any other link from a stranger: checked field by field.
Future<SharedLink?> resolveShortLink(String code, {http.Client? client}) async {
  if (!ShareService.shortCodePattern.hasMatch(code)) return null;
  final c = client ?? http.Client();
  try {
    final r = await c.get(Uri.parse('${CloudService.baseUrl}/link.php?c=$code')).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body);
    if (j is! Map) return null;
    if (j['t'] == 'playlist') {
      final ids = (j['ids'] is List ? j['ids'] as List : const []).map((e) => '$e').where(_idPattern.hasMatch).take(ShareService.maxSongs).toList();
      if (ids.isEmpty) return null;
      var name = '${j['n'] ?? ''}'.trim();
      if (name.isEmpty) name = 'Shared playlist';
      return SharedPlaylist(name.length > 80 ? name.substring(0, 80) : name, ids);
    }
    final id = '${j['id'] ?? ''}';
    if (!_idPattern.hasMatch(id)) return null;
    final title = '${j['s'] ?? ''}'.trim();
    return SharedSong(id, title.length > 120 ? title.substring(0, 120) : title);
  } catch (_) {
    return null;
  } finally {
    if (client == null) c.close();
  }
}

/// Reads a voice "play `<query>`" request (`samgeet://play?q=...`, built by `MainActivity`).
/// Gives the spoken query (empty for just "play music"), or null if [raw] isn't one.
String? parseVoiceQuery(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null || u.scheme != 'samgeet' || u.host != 'play') return null;
  final q = (u.queryParameters['q'] ?? '').trim();
  return q.length > 200 ? q.substring(0, 200) : q;
}

/// Bridge to `MainActivity`, which receives the link when the app is opened from one.
class DeepLinks {
  static const _channel = MethodChannel('app.samgeet.music/links');

  final _controller = StreamController<String>.broadcast();

  DeepLinks() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) _controller.add(call.arguments as String);
    });
  }

  /// The link that launched the app, if any. Only returns it once.
  Future<String?> initial() async {
    try {
      return await _channel.invokeMethod<String>('initialLink');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Links tapped while the app is already running.
  Stream<String> get links => _controller.stream;

  void dispose() => _controller.close();
}
