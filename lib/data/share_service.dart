import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
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
/// Songs and playlists are shared as a short link, `https://api.sambitmaity.fun/s/<code>`, that the
/// server (`backend/api/link.php`) maps to the song or playlist; it opens the landing page
/// (`backend/api/share.php`: details plus a "download the app" button), or the app itself. Offline,
/// the old long link is used instead: the song's details in the query, and for a playlist a compact
/// code in its `#p=` fragment, so "Import playlist" still works from a pasted message.
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

  // ---------- short links: https://api.sambitmaity.fun/s/<code> (backend/api/link.php) ----------
  static const shortCodeChars = '23456789abcdefghjkmnpqrstuvwxyz';
  static final shortCodePattern = RegExp('^[$shortCodeChars]{7}\$');

  /// Asks the server for a short link standing for [payload]; null if it can't be reached.
  static Future<String?> _shortLink(Map<String, Object> payload, http.Client? client) async {
    final c = client ?? http.Client();
    try {
      final r = await c
          .post(Uri.parse('${CloudService.baseUrl}/link.php'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final code = (jsonDecode(r.body) as Map)['code'];
      return code is String && shortCodePattern.hasMatch(code) ? '${CloudService.baseUrl}/s/$code' : null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// A short link to [t], or the long one if the server can't be reached.
  static Future<String> shortSongLink(Track t, {http.Client? client}) async =>
      await _shortLink({
        't': 'song',
        'id': t.id,
        's': t.title,
        if (t.artists.isNotEmpty) 'a': t.artistLine,
        if (t.album.isNotEmpty) 'al': t.album,
        if (t.image.isNotEmpty) 'i': t.art(500),
      }, client) ??
      songLink(t);

  /// A short link to a playlist, or the long one (which carries the songs itself) when offline.
  static Future<String> shortPlaylistLink(String name, List<Track> tracks, {http.Client? client}) async =>
      await _shortLink({'t': 'playlist', 'n': name, 'ids': tracks.map((t) => t.id).take(maxSongs).toList()}, client) ??
      playlistLink(name, tracks);

  static Future<void> shareTrack(Track t) async {
    final link = await shortSongLink(t);
    await SharePlus.instance.share(ShareParams(
      text: '🎵 ${t.title} · ${t.primaryArtist}\nListen on Samgeet 👉 $link',
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

  static Future<void> sharePlaylist(String name, List<Track> tracks) async {
    final link = await shortPlaylistLink(name, tracks);
    final firstFew = tracks.take(3).map((t) => t.title).join(', ');
    final more = tracks.length > 3 ? ' and ${tracks.length - 3} more' : '';
    await SharePlus.instance.share(ShareParams(
      text: '🎧 $name · ${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}\n'
          '${firstFew.isEmpty ? '' : '$firstFew$more\n'}'
          'Open in Samgeet 👉 $link',
      subject: name,
    ));
  }

  static Future<void> shareUserPlaylist(UserPlaylist p) => sharePlaylist(p.name, p.tracks);
}
