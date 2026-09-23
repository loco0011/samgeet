import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';

/// A newer version of the app, as published on the GitHub releases page.
class AppUpdate {
  final String version; // "1.3.2"
  final String notes; // release notes, lightly cleaned for display
  final String downloadUrl; // the APK, or the release page if it has none
  final bool required; // the notes contain "[required]": no "Later" button

  const AppUpdate({required this.version, required this.notes, required this.downloadUrl, this.required = false});

  /// Reads the GitHub "latest release" response. Returns null if it isn't
  /// newer than [current] (or can't be understood).
  static AppUpdate? fromRelease(Map<String, dynamic> j, {String current = kVersionName}) {
    final version = '${j['tag_name'] ?? ''}'.trim().replaceFirst(RegExp('^[vV]'), '');
    if (version.isEmpty || j['draft'] == true || j['prerelease'] == true) return null;
    if (compareVersions(version, current) <= 0) return null;

    final assets = j['assets'] is List ? (j['assets'] as List).whereType<Map>() : const <Map>[];
    final apk = assets.where((a) => '${a['name']}'.toLowerCase().endsWith('.apk')).firstOrNull;
    final body = '${j['body'] ?? ''}';
    // Only ever open this project's own GitHub pages, whatever the response says.
    final link = [apk?['browser_download_url'], j['html_url']].map((u) => '${u ?? ''}').where(isTrustedLink).firstOrNull;
    return AppUpdate(
      version: version,
      notes: cleanNotes(body),
      downloadUrl: link ?? '$kSourceCodeUrl/releases/latest',
      required: body.toLowerCase().contains('[required]'),
    );
  }

  /// True for https links inside this project on GitHub (release pages and downloads).
  static bool isTrustedLink(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host != 'github.com' || u.hasPort || u.userInfo.isNotEmpty) return false;
    final base = Uri.parse(kSourceCodeUrl).path; // "/loco0011/samgeet"
    return u.path.startsWith('$base/releases/') && !u.path.contains('..');
  }

  /// Compares dotted versions: negative if a < b, 0 if equal, positive if a > b.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v.split(RegExp(r'[.+-]')).map((p) => int.tryParse(p) ?? 0).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  /// Release notes without the install steps, checksum and Markdown symbols.
  static String cleanNotes(String body) {
    final cut = body.indexOf(RegExp(r'^#+\s*Install', multiLine: true));
    var s = cut >= 0 ? body.substring(0, cut) : body;
    s = s
        .replaceAll(RegExp(r'\[required\]', caseSensitive: false), '')
        .replaceAll(RegExp(r'^#+\s*.*$', multiLine: true), '') // headings ("## Samgeet 1.3.2")
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ')
        .replaceAll('**', '')
        .replaceAll('`', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return s.trim();
  }
}

/// Checks GitHub for a newer release, at most a few times a day.
class UpdateService {
  static const _skipKey = 'update_skip_version';
  static const _checkedKey = 'update_last_check';

  final http.Client _client;
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// The newer version, or null if there's none (or the check failed).
  /// Automatic checks ([manual] = false) respect "Skip this version" and only
  /// run every 6 hours; a check from the About screen always runs.
  Future<AppUpdate?> check({bool manual = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!manual) {
      final last = prefs.getInt(_checkedKey) ?? 0;
      if (now - last < const Duration(hours: 6).inMilliseconds) return null;
    }
    try {
      final res = await _client
          .get(Uri.parse(kLatestReleaseApi), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('GitHub returned ${res.statusCode}');
      await prefs.setInt(_checkedKey, now);
      final update = AppUpdate.fromRelease(Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map));
      if (update == null) return null;
      if (!manual && !update.required && prefs.getString(_skipKey) == update.version) return null;
      return update;
    } catch (_) {
      if (manual) rethrow;
      return null;
    }
  }

  Future<void> skip(String version) async => (await SharedPreferences.getInstance()).setString(_skipKey, version);
}
