import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';
import 'saavn_api.dart';
import 'track.dart';

/// A song saved on the phone for offline listening.
class DownloadedSong {
  final Track track;
  final String file;
  final String art; // '' when the cover couldn't be saved
  final int bytes;
  final int kbps;
  final int savedAt;
  const DownloadedSong({required this.track, required this.file, this.art = '', this.bytes = 0, this.kbps = 0, this.savedAt = 0});

  Map<String, dynamic> toJson() => {'track': track.toJson(), 'file': file, 'art': art, 'bytes': bytes, 'kbps': kbps, 'at': savedAt};

  static DownloadedSong? fromJson(Object? j) {
    if (j is! Map || j['track'] is! Map || '${j['file'] ?? ''}'.isEmpty) return null;
    return DownloadedSong(
      track: Track.fromStored(Map<String, dynamic>.from(j['track'] as Map)),
      file: '${j['file']}',
      art: '${j['art'] ?? ''}',
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      kbps: (j['kbps'] as num?)?.toInt() ?? 0,
      savedAt: (j['at'] as num?)?.toInt() ?? 0,
    );
  }
}

enum DownloadState { none, queued, downloading, done, failed }

/// Saves songs to the phone so they play without a connection, at the same
/// quality as streaming (the very same audio file, up to 320 kbps).
///
/// Files live in the app's private storage, in Android's `no_backup` folder:
/// other apps can't read them, they don't fill the phone's cloud backup, and
/// they go away when the app is uninstalled. What's downloaded is listed in
/// [SharedPreferences] under `dl.index`, which is kept out of account sync
/// (each phone has its own downloads).
class DownloadService extends ChangeNotifier {
  static const indexPref = 'dl.index';
  static const qualityPref = 'dl.quality';
  static const _parallel = 2;

  final SharedPreferences _prefs;
  final SaavnApi _api;
  final http.Client _http;
  final Future<Directory> Function() _dir;

  /// Records what gets downloaded. Null in tests.
  Analytics? analytics;

  DownloadService(this._prefs, this._api, {http.Client? client, Future<Directory> Function()? dir})
      : _http = client ?? http.Client(),
        _dir = dir ?? defaultDirectory;

  /// Downloaded songs, newest first.
  final LinkedHashMap<String, DownloadedSong> _done = LinkedHashMap();
  final Map<String, double> _progress = {}; // 0..1 while downloading, -1 while waiting
  final Set<String> _failed = {};
  final Queue<Track> _queue = Queue();
  final Set<String> _cancelled = {};
  final Set<String> _running = {};
  int _active = 0;

  final StreamController<String> _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  AudioQuality quality = AudioQuality.high;

  /// Cover files by artwork address (sizes stripped), so artwork shows offline anywhere in the app.
  static final Map<String, String> _artByUrl = {};

  static String _artKey(String url) => url.replaceAll(RegExp(r'\d+x\d+'), '').replaceFirst('http://', 'https://');

  /// The saved cover for an artwork address, if that song was downloaded.
  static String? localArt(String url) => url.isEmpty ? null : _artByUrl[_artKey(url)];

  static Future<Directory> defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    // Android keeps no_backup next to files/ and never copies it to the cloud backup.
    final base = !kIsWeb && Platform.isAndroid ? Directory('${support.parent.path}/no_backup') : support;
    return Directory('${base.path}/offline').create(recursive: true);
  }

  /// Reads the list, dropping songs whose file has gone missing.
  Future<void> init() async {
    quality = AudioQuality.values.firstWhere((q) => q.kbps == (_prefs.getInt(qualityPref) ?? 320), orElse: () => AudioQuality.high);
    final list = decodeIndex(_prefs.getString(indexPref));
    var missing = false;
    for (final d in list) {
      if (await File(d.file).exists()) {
        _done[d.track.id] = d;
        _register(d);
      } else {
        missing = true;
      }
    }
    if (missing) await _saveIndex();
    notifyListeners();
  }

  static List<DownloadedSong> decodeIndex(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final j in jsonDecode(raw) as List) ?DownloadedSong.fromJson(j)];
    } catch (_) {
      return const [];
    }
  }

  void _register(DownloadedSong d) {
    if (d.art.isNotEmpty && d.track.image.isNotEmpty) _artByUrl[_artKey(d.track.image)] = d.art;
  }

  Future<void> _saveIndex() => _prefs.setString(indexPref, jsonEncode([for (final d in _done.values) d.toJson()]));

  // ---------- reading ----------
  List<Track> get songs => [for (final d in _done.values) d.track];
  List<DownloadedSong> get items => _done.values.toList();
  int get count => _done.length;
  int get totalBytes => _done.values.fold(0, (s, d) => s + d.bytes);
  bool get busy => _progress.isNotEmpty;
  int get pending => _progress.length;

  bool isDownloaded(String id) => _done.containsKey(id);
  String? fileFor(String id) => _done[id]?.file;
  String? artFor(String id) {
    final a = _done[id]?.art;
    return a == null || a.isEmpty ? null : a;
  }

  DownloadState stateOf(String id) {
    if (_done.containsKey(id)) return DownloadState.done;
    final p = _progress[id];
    if (p != null) return p < 0 ? DownloadState.queued : DownloadState.downloading;
    if (_failed.contains(id)) return DownloadState.failed;
    return DownloadState.none;
  }

  /// 0..1 while downloading, null otherwise.
  double? progressOf(String id) {
    final p = _progress[id];
    return p == null || p < 0 ? null : p;
  }

  // ---------- settings ----------
  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    notifyListeners();
    await _prefs.setInt(qualityPref, q.kbps);
  }

  // ---------- downloading ----------
  void download(Track t) => downloadAll([t]);

  /// Queues every song not already saved or on its way. Returns how many were queued.
  int downloadAll(Iterable<Track> tracks) {
    var n = 0;
    for (final t in tracks) {
      if (t.id.isEmpty || _done.containsKey(t.id) || _progress.containsKey(t.id)) continue;
      _failed.remove(t.id);
      _cancelled.remove(t.id);
      n++;
      if (_running.contains(t.id)) {
        _progress[t.id] = 0; // cancelled a moment ago and still winding down: let it carry on
        continue;
      }
      _progress[t.id] = -1;
      _queue.add(t);
      analytics?.log('download', track: t, value: quality.name);
    }
    if (n > 0) {
      notifyListeners();
      _pump();
    }
    return n;
  }

  void cancel(String id) {
    if (!_progress.containsKey(id)) return;
    _cancelled.add(id);
    _queue.removeWhere((t) => t.id == id);
    _progress.remove(id);
    notifyListeners();
  }

  void cancelAll() {
    for (final id in _progress.keys) {
      _cancelled.add(id);
    }
    _queue.clear();
    _progress.clear();
    notifyListeners();
  }

  void _pump() {
    while (_active < _parallel && _queue.isNotEmpty) {
      final t = _queue.removeFirst();
      _active++;
      unawaited(_fetch(t).whenComplete(() {
        _active--;
        _pump();
      }));
    }
  }

  Future<void> _fetch(Track t) async {
    _running.add(t.id);
    final dir = await _dir();
    final part = File('${dir.path}/${t.id}.part');
    try {
      var track = t;
      if (!track.isPlayable) track = (await _api.details([t.id])).firstOrNull ?? t;
      var res = await _open(track);
      if (res == null || res.statusCode != 200) {
        // The address may have gone stale; ask for a fresh one once.
        final fresh = (await _api.details([t.id])).firstOrNull;
        if (fresh != null) track = t.copyWithUrl(fresh);
        res = await _open(track);
      }
      if (res == null || res.statusCode != 200) throw const HttpException('not available');

      final kbps = _kbps(track);
      final total = res.contentLength ?? 0;
      var got = 0;
      var shown = 0.0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res.stream) {
          if (_cancelled.contains(t.id)) break;
          sink.add(chunk);
          got += chunk.length;
          final p = total > 0 ? got / total : 0.0;
          if (p - shown >= 0.02) {
            shown = p;
            _progress[t.id] = p;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (_cancelled.remove(t.id)) {
        await _delete(part.path);
        return;
      }
      if (got == 0 || (total > 0 && got < total)) throw const HttpException('incomplete');

      final file = await part.rename('${dir.path}/${t.id}.m4a');
      final art = await _saveArt(track, dir);
      final d = DownloadedSong(track: t, file: file.path, art: art, bytes: got, kbps: kbps, savedAt: DateTime.now().millisecondsSinceEpoch);
      final rest = _done.values.where((x) => x.track.id != t.id).toList();
      _done
        ..clear()
        ..[t.id] = d;
      for (final x in rest) {
        _done[x.track.id] = x;
      }
      _register(d);
      await _saveIndex();
    } catch (e) {
      await _delete(part.path);
      if (!_cancelled.remove(t.id)) {
        _failed.add(t.id);
        _messages.add(e is FileSystemException
            ? 'Not enough space on your phone to save "${t.title}"'
            : 'Couldn\'t download "${t.title}". Check your connection and try again.');
      }
    } finally {
      _running.remove(t.id);
      _progress.remove(t.id);
      notifyListeners();
    }
  }

  int _kbps(Track t) => quality == AudioQuality.high && !t.has320 ? 160 : quality.kbps;

  Future<http.StreamedResponse?> _open(Track t) async {
    final url = t.streamUrl(quality);
    if (url.isEmpty) return null;
    try {
      return await _http.send(http.Request('GET', Uri.parse(url))).timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  Future<String> _saveArt(Track t, Directory dir) async {
    if (t.image.isEmpty) return '';
    try {
      final res = await _http.get(Uri.parse(t.art(500))).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return '';
      final f = File('${dir.path}/${t.id}.jpg');
      await f.writeAsBytes(res.bodyBytes);
      return f.path;
    } catch (_) {
      return '';
    }
  }

  // ---------- removing ----------
  Future<void> remove(String id) async {
    final d = _done.remove(id);
    if (d == null) return;
    analytics?.log('download_remove', value: id);
    notifyListeners();
    await _delete(d.file);
    if (d.art.isNotEmpty) {
      _artByUrl.removeWhere((_, v) => v == d.art);
      await _delete(d.art);
    }
    await _saveIndex();
  }

  Future<void> removeAll() async {
    cancelAll();
    final all = _done.values.toList();
    _done.clear();
    _artByUrl.clear();
    notifyListeners();
    for (final d in all) {
      await _delete(d.file);
      if (d.art.isNotEmpty) await _delete(d.art);
    }
    await _saveIndex();
  }

  static Future<void> _delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// "12.4 MB"
  static String size(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  @override
  void dispose() {
    cancelAll();
    _messages.close();
    _http.close();
    super.dispose();
  }
}
