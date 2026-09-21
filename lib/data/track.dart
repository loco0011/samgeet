import 'dart:convert';

import 'package:dart_des/dart_des.dart';

/// A lightweight reference to an artist.
class ArtistRef {
  final String id;
  final String name;
  final String image;
  const ArtistRef({required this.id, required this.name, this.image = ''});

  factory ArtistRef.fromJson(Map<String, dynamic> j) => ArtistRef(
        id: '${j['id'] ?? ''}',
        name: _clean('${j['name'] ?? ''}'),
        image: '${j['image'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'image': image};

  @override
  bool operator ==(Object other) => other is ArtistRef && other.id == id && other.name == name;
  @override
  int get hashCode => Object.hash(id, name);
}

/// Audio quality tiers offered by the source (kbps).
enum AudioQuality {
  low(96, 'Data saver', '96 kbps'),
  medium(160, 'Balanced', '160 kbps'),
  high(320, 'High quality', '320 kbps');

  final int kbps;
  final String label;
  final String detail;
  const AudioQuality(this.kbps, this.label, this.detail);
}

String _clean(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// Decrypts the source's `encrypted_media_url` into a real stream URL.
String decryptMediaUrl(String encrypted) {
  if (encrypted.isEmpty) return '';
  try {
    final des = DES(
      key: utf8.encode('38346591'),
      mode: DESMode.ECB,
      paddingType: DESPaddingType.PKCS5,
    );
    final out = des.decrypt(base64.decode(encrypted));
    final url = utf8.decode(out, allowMalformed: true).trim();
    return url.startsWith('http') ? url : '';
  } catch (_) {
    return '';
  }
}

class Track {
  final String id;
  final String title;
  final List<ArtistRef> artists;
  final String album;
  final String albumId;
  final String image; // 150x150 URL from source; use [art] for sizes
  final String language;
  final int year;
  final int playCount;
  final int durationSec;
  final String encryptedUrl;
  final bool has320;
  final bool hasLyrics;
  final String permaUrl;

  const Track({
    required this.id,
    required this.title,
    this.artists = const [],
    this.album = '',
    this.albumId = '',
    this.image = '',
    this.language = '',
    this.year = 0,
    this.playCount = 0,
    this.durationSec = 0,
    this.encryptedUrl = '',
    this.has320 = false,
    this.hasLyrics = false,
    this.permaUrl = '',
  });

  String get artistLine => artists.isEmpty ? 'Unknown artist' : artists.map((a) => a.name).toSet().join(', ');
  String get primaryArtist => artists.isEmpty ? '' : artists.first.name;
  int get decade => year <= 0 ? 0 : (year ~/ 10) * 10;
  bool get isPlayable => encryptedUrl.isNotEmpty;
  Duration get duration => Duration(seconds: durationSec);

  /// Artwork at a requested square size (the CDN serves 50/150/500).
  String art([int size = 500]) => image
      .replaceAll('150x150', '${size}x$size')
      .replaceAll('50x50', '${size}x$size')
      .replaceAll('250x250', '${size}x$size');

  /// Resolves the stream URL for the requested quality (falls back gracefully).
  String streamUrl(AudioQuality q) {
    final base = decryptMediaUrl(encryptedUrl);
    if (base.isEmpty) return '';
    var kbps = q.kbps;
    if (kbps == 320 && !has320) kbps = 160;
    return base.replaceAll(RegExp(r'_(96|160|320)\.mp4'), '_$kbps.mp4');
  }

  factory Track.fromJson(Map<String, dynamic> j) {
    final mi = (j['more_info'] is Map) ? Map<String, dynamic>.from(j['more_info']) : <String, dynamic>{};
    final artistMap = mi['artistMap'] is Map ? Map<String, dynamic>.from(mi['artistMap']) : <String, dynamic>{};

    List<ArtistRef> artists = [];
    final primary = artistMap['primary_artists'];
    if (primary is List && primary.isNotEmpty) {
      artists = primary.whereType<Map>().map((m) => ArtistRef.fromJson(Map<String, dynamic>.from(m))).toList();
    }
    if (artists.isEmpty && artistMap['artists'] is List) {
      artists = (artistMap['artists'] as List)
          .whereType<Map>()
          .where((m) => m['role'] == 'singer')
          .map((m) => ArtistRef.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    if (artists.isEmpty) {
      final sub = '${j['subtitle'] ?? ''}';
      final line = sub.split(' - ').first;
      artists = line
          .split(',')
          .map((s) => _clean(s))
          .where((s) => s.isNotEmpty)
          .map((n) => ArtistRef(id: '', name: n))
          .toList();
    }

    int toInt(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;
    return Track(
      id: '${j['id']}',
      title: _clean('${j['title'] ?? j['song'] ?? ''}'),
      artists: artists,
      album: _clean('${mi['album'] ?? ''}'),
      albumId: '${mi['album_id'] ?? ''}',
      image: '${j['image'] ?? ''}',
      language: '${j['language'] ?? ''}'.toLowerCase(),
      year: toInt(j['year']),
      playCount: toInt(j['play_count']),
      durationSec: toInt(mi['duration']),
      encryptedUrl: '${mi['encrypted_media_url'] ?? j['encrypted_media_url'] ?? ''}',
      has320: '${mi['320kbps']}' == 'true',
      hasLyrics: '${mi['has_lyrics']}' == 'true',
      permaUrl: '${j['perma_url'] ?? ''}',
    );
  }

  /// Compact form for persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artists': artists.map((a) => a.toJson()).toList(),
        'album': album,
        'albumId': albumId,
        'image': image,
        'language': language,
        'year': year,
        'playCount': playCount,
        'durationSec': durationSec,
        'enc': encryptedUrl,
        'has320': has320,
        'hasLyrics': hasLyrics,
        'permaUrl': permaUrl,
      };

  factory Track.fromStored(Map<String, dynamic> j) => Track(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        artists: ((j['artists'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ArtistRef.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        album: '${j['album'] ?? ''}',
        albumId: '${j['albumId'] ?? ''}',
        image: '${j['image'] ?? ''}',
        language: '${j['language'] ?? ''}',
        year: (j['year'] as num?)?.toInt() ?? 0,
        playCount: (j['playCount'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
        encryptedUrl: '${j['enc'] ?? ''}',
        has320: j['has320'] == true,
        hasLyrics: j['hasLyrics'] == true,
        permaUrl: '${j['permaUrl'] ?? ''}',
      );

  Track copyWithUrl(Track fresh) => Track(
        id: id,
        title: title,
        artists: artists,
        album: album,
        albumId: albumId,
        image: image,
        language: language,
        year: year,
        playCount: playCount,
        durationSec: durationSec,
        encryptedUrl: fresh.encryptedUrl,
        has320: fresh.has320,
        hasLyrics: hasLyrics,
        permaUrl: permaUrl,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// A generic "card" for browse shelves: a song, album, playlist, artist or chart.
enum CardKind { song, album, playlist, artist, chart, radio }

class MediaCard {
  final CardKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String image;
  final String permaUrl;
  const MediaCard({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.permaUrl = '',
  });

  String art([int size = 500]) => image
      .replaceAll('150x150', '${size}x$size')
      .replaceAll('50x50', '${size}x$size')
      .replaceAll('250x250', '${size}x$size');

  static CardKind? _kind(String t) {
    switch (t) {
      case 'song':
        return CardKind.song;
      case 'album':
        return CardKind.album;
      case 'playlist':
        return CardKind.playlist;
      case 'artist':
        return CardKind.artist;
      case 'chart':
        return CardKind.chart;
      case 'radio_station':
        return CardKind.radio;
    }
    return null;
  }

  static MediaCard? fromJson(Map<String, dynamic> j) {
    final k = _kind('${j['type']}');
    if (k == null) return null;
    final title = _clean('${j['title'] ?? j['name'] ?? ''}');
    if (title.isEmpty) return null;
    return MediaCard(
      kind: k,
      id: '${j['id']}',
      title: title,
      subtitle: _clean('${j['subtitle'] ?? j['header_desc'] ?? ''}'),
      image: '${j['image'] ?? ''}',
      permaUrl: '${j['perma_url'] ?? ''}',
    );
  }
}

/// A resolved list of songs plus header info (album / playlist / artist page).
class Collection {
  final String id;
  final String title;
  final String subtitle;
  final String image;
  final List<Track> tracks;
  final String permaUrl;
  const Collection({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.tracks = const [],
    this.permaUrl = '',
  });

  String art([int size = 500]) => image
      .replaceAll('150x150', '${size}x$size')
      .replaceAll('50x50', '${size}x$size')
      .replaceAll('250x250', '${size}x$size');
}
