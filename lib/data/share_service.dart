import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'library_store.dart';
import 'track.dart';

/// Sharing songs and playlists.
///
/// Playlists are shared as readable text *plus* a compact code. Anyone with
/// Samgeet can paste the message into "Import playlist" and get the same list.
class ShareService {
  static const _prefix = 'samgeet://p/';
  // Codes shared before the app was renamed still import.
  static const _legacyPrefix = 'sangeet://p/';

  static Future<void> shareTrack(Track t) {
    final link = t.permaUrl.isNotEmpty ? '\n${t.permaUrl}' : '';
    return SharePlus.instance.share(ShareParams(
      text: '🎵 ${t.title} — ${t.artistLine}$link\n\nShared from Samgeet',
      subject: t.title,
    ));
  }

  static String encodePlaylist(String name, List<Track> tracks) {
    final payload = jsonEncode({'n': name, 'i': tracks.map((t) => t.id).toList()});
    final packed = base64Url.encode(gzip.encode(utf8.encode(payload)));
    return '$_prefix$packed';
  }

  /// Returns (name, songIds) if [text] contains a Samgeet playlist code.
  static ({String name, List<String> ids})? decodePlaylist(String text) {
    final m = RegExp('(?:${RegExp.escape(_prefix)}|${RegExp.escape(_legacyPrefix)})([A-Za-z0-9_=-]+)').firstMatch(text);
    if (m == null) return null;
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(base64Url.decode(m.group(1)!)))) as Map;
      final ids = (json['i'] as List).map((e) => '$e').toList();
      if (ids.isEmpty) return null;
      return (name: '${json['n'] ?? 'Shared playlist'}', ids: ids);
    } catch (_) {
      return null;
    }
  }

  static Future<void> sharePlaylist(String name, List<Track> tracks) {
    final shown = tracks.take(15).toList();
    final lines = [
      for (var i = 0; i < shown.length; i++) '${i + 1}. ${shown[i].title} — ${shown[i].primaryArtist}',
      if (tracks.length > shown.length) '…and ${tracks.length - shown.length} more',
    ];
    return SharePlus.instance.share(ShareParams(
      text: '🎧 "$name" on Samgeet (${tracks.length} songs)\n\n${lines.join('\n')}\n\n'
          'Open Samgeet → Library → Import, and paste this message:\n${encodePlaylist(name, tracks)}',
      subject: name,
    ));
  }

  static Future<void> shareUserPlaylist(UserPlaylist p) => sharePlaylist(p.name, p.tracks);
}
