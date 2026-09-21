import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'cloud_service.dart';
import 'library_store.dart';
import 'track.dart';

class _CappedSink implements Sink<List<int>> {
  final BytesBuilder _out;
  final int _limit;
  _CappedSink(this._out, this._limit);

  @override
  void add(List<int> chunk) {
    _out.add(chunk);
    if (_out.length > _limit) throw const FormatException('playlist code too large');
  }

  @override
  void close() {}
}

/// Sharing songs and playlists.
///
/// Songs and playlists are shared as a link to the landing page on Samgeet's server
/// (`backend/api/share.php`): song/playlist info plus a "download the app" button. A playlist link
/// also carries a compact code in its `#p=` fragment (the fragment never reaches the server), so
/// anyone with Samgeet can paste the message into "Import playlist" and get the same list.
class ShareService {
  static const _prefix = 'samgeet://p/';
  // Codes shared before the app was renamed still import.
  static const _legacyPrefix = 'sangeet://p/';

  static const _pageUrl = '${CloudService.baseUrl}/share.php';

  static String songLink(Track t) => Uri.parse(_pageUrl).replace(queryParameters: {
        't': 'song',
        'id': t.id,
        's': t.title,
        if (t.artists.isNotEmpty) 'a': t.artistLine,
        if (t.album.isNotEmpty) 'al': t.album,
        if (t.image.isNotEmpty) 'i': t.art(500),
      }).toString();

  static String playlistLink(String name, List<Track> tracks) =>
      '${Uri.parse(_pageUrl).replace(queryParameters: {'t': 'playlist', 'n': name, 'c': '${tracks.length}'})}'
      '#p=${encodePlaylist(name, tracks, withPrefix: false)}';

  static Future<void> shareTrack(Track t) {
    return SharePlus.instance.share(ShareParams(
      text: '🎵 ${t.title} — ${t.artistLine}\n\nListen on Samgeet, the ad-free music player:\n${songLink(t)}',
      subject: t.title,
    ));
  }

  static String encodePlaylist(String name, List<Track> tracks, {bool withPrefix = true}) {
    final payload = jsonEncode({'n': name, 'i': tracks.map((t) => t.id).toList()});
    final packed = base64Url.encode(gzip.encode(utf8.encode(payload)));
    return withPrefix ? '$_prefix$packed' : packed;
  }

  // A pasted code is untrusted input: cap it before and after decompression so a tiny
  // crafted code can't expand into gigabytes and crash the app.
  static const maxCodeChars = 40000;
  static const maxPayloadBytes = 256 * 1024;
  static const maxSongs = 500;

  /// Returns (name, songIds) if [text] contains a Samgeet playlist code.
  static ({String name, List<String> ids})? decodePlaylist(String text) {
    final m = RegExp('(?:${RegExp.escape(_prefix)}|${RegExp.escape(_legacyPrefix)}|#p=)([A-Za-z0-9_=-]+)').firstMatch(text);
    if (m == null) return null;
    final code = m.group(1)!;
    if (code.length > maxCodeChars) return null;
    try {
      final raw = _gunzipCapped(base64Url.decode(code), maxPayloadBytes);
      final json = jsonDecode(utf8.decode(raw)) as Map;
      final ids = (json['i'] as List).map((e) => '$e').where((s) => s.isNotEmpty && s.length <= 64).take(maxSongs).toList();
      if (ids.isEmpty) return null;
      var name = '${json['n'] ?? 'Shared playlist'}'.trim();
      if (name.isEmpty) name = 'Shared playlist';
      if (name.length > 80) name = name.substring(0, 80);
      return (name: name, ids: ids);
    } catch (_) {
      return null;
    }
  }

  /// Gunzips [data], throwing as soon as the output would pass [limit] bytes.
  static List<int> _gunzipCapped(List<int> data, int limit) {
    final out = BytesBuilder(copy: false);
    final sink = _CappedSink(out, limit);
    final conv = gzip.decoder.startChunkedConversion(sink);
    conv.add(data);
    conv.close();
    return out.takeBytes();
  }

  static Future<void> sharePlaylist(String name, List<Track> tracks) {
    final shown = tracks.take(15).toList();
    final lines = [
      for (var i = 0; i < shown.length; i++) '${i + 1}. ${shown[i].title} — ${shown[i].primaryArtist}',
      if (tracks.length > shown.length) '…and ${tracks.length - shown.length} more',
    ];
    return SharePlus.instance.share(ShareParams(
      text: '🎧 "$name" on Samgeet (${tracks.length} songs)\n\n${lines.join('\n')}\n\n'
          'Get Samgeet and import it (Library → Import → paste this message):\n${playlistLink(name, tracks)}',
      subject: name,
    ));
  }

  static Future<void> shareUserPlaylist(UserPlaylist p) => sharePlaylist(p.name, p.tracks);
}
