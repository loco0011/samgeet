import 'dart:async';

import 'package:flutter/services.dart';

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
