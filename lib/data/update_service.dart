import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import 'app_config.dart';
import 'cloud_service.dart';

/// One headline from the release notes: "🎨 **Make the player yours.** Pick from…" becomes
/// (icon: 🎨, title: Make the player yours).
class Highlight {
  final String icon; // an emoji, or '' when the note has none
  final String title;
  const Highlight(this.icon, this.title);

  /// The headlines of [notes], at most [max]. Bullets with a bold lead give that lead; others give
  /// their first sentence, kept short.
  static List<Highlight> parse(String notes, {int max = 8}) {
    final out = <Highlight>[];
    for (final line in notes.split('\n')) {
      final m = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
      if (m == null) continue;
      var rest = m.group(1)!.trim();
      // Leading emoji (anything before the first letter, digit or "**").
      final lead = RegExp(r'^([^\p{L}\p{N}*]+)', unicode: true).firstMatch(rest);
      var icon = '';
      if (lead != null) {
        icon = lead.group(1)!.trim();
        rest = rest.substring(lead.end).trim();
      }
      final bold = RegExp(r'^\*\*(.+?)\*\*').firstMatch(rest);
      var title = bold != null ? bold.group(1)! : rest.split(RegExp(r'(?<=[.!?])\s')).first;
      title = title.replaceAll('**', '').trim().replaceFirst(RegExp(r'[.:]$'), '');
      if (title.length > 48) title = '${title.substring(0, 46).trimRight()}…';
      if (title.isEmpty) continue;
      out.add(Highlight(icon, title));
      if (out.length >= max) break;
    }
    return out;
  }
}

/// A newer version of the app, as published from the admin panel (or, for builds without the
/// server key, on the GitHub releases page).
class AppUpdate {
  final String version; // "1.3.2"
  final String notes; // release notes, lightly cleaned for display
  final List<Highlight> highlights; // the headlines, for the popup
  final String downloadUrl; // the APK, or the release page if it has none
  final bool required; // no "Later" button
  final int? sizeBytes;

  const AppUpdate({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.highlights = const [],
    this.required = false,
    this.sizeBytes,
  });

  Map<String, Object?> toJson() => {
        'version': version, 'notes': notes, 'url': downloadUrl, 'required': required, 'size': sizeBytes, //
        'highlights': [for (final h in highlights) [h.icon, h.title]],
      };

  static AppUpdate? fromJson(Object? j) {
    if (j is! Map || j['version'] is! String || j['url'] is! String) return null;
    return AppUpdate(
      version: j['version'] as String,
      notes: '${j['notes'] ?? ''}',
      downloadUrl: j['url'] as String,
      required: j['required'] == true,
      sizeBytes: j['size'] is int ? j['size'] as int : null,
      highlights: [
        for (final h in (j['highlights'] is List ? j['highlights'] as List : const []))
          if (h is List && h.length == 2) Highlight('${h[0]}', '${h[1]}'),
      ],
    );
  }

  /// Reads the `update` object from the server's config (already known to be newer).
  static AppUpdate? fromServer(Object? j, {String current = kVersionName}) {
    if (j is! Map) return null;
    final version = '${j['version'] ?? ''}'.trim();
    final url = '${j['url'] ?? ''}';
    if (version.isEmpty || !isTrustedLink(url)) return null;
    final build = j['build'];
    if (build is int ? build <= kBuildNumber : compareVersions(version, current) <= 0) return null;
    return AppUpdate(
      version: version,
      notes: cleanNotes('${j['notes'] ?? ''}'),
      highlights: Highlight.parse('${j['notes'] ?? ''}'),
      downloadUrl: url,
      required: j['required'] == true,
      sizeBytes: j['size'] is int ? j['size'] as int : null,
    );
  }

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
      highlights: Highlight.parse(body),
      downloadUrl: link ?? '$kSourceCodeUrl/releases/latest',
      required: body.toLowerCase().contains('[required]'),
    );
  }

  /// True for https links inside this project on GitHub (release pages and downloads), and APKs
  /// uploaded to Samgeet's own server.
  static bool isTrustedLink(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.hasPort || u.userInfo.isNotEmpty || u.path.contains('..')) return false;
    if (u.host == Uri.parse(CloudService.baseUrl).host) return u.path.toLowerCase().endsWith('.apk');
    if (u.host != 'github.com') return false;
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

/// Looks for a newer version: in what the admin panel published (fetched by [AppConfig] when the
/// app opens), or on GitHub for builds that don't talk to Samgeet's server.
class UpdateService {
  static const _skipKey = 'update_skip_version';
  static const _checkedKey = 'update_last_check';

  final http.Client _client;
  final AppConfig? config;
  UpdateService({http.Client? client, this.config}) : _client = client ?? http.Client();

  /// The newer version, or null if there's none (or the check failed).
  /// Automatic checks ([manual] = false) respect "Skip this version"; a check from the About
  /// screen always asks again. Required updates are always offered.
  Future<AppUpdate?> check({bool manual = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cfg = config;
    if (cfg != null && cfg.api.configured) {
      if (manual || !cfg.loaded) {
        final ok = await cfg.refresh();
        if (!ok && manual) throw Exception('Samgeet\'s server could not be reached');
      }
      final update = cfg.update;
      if (update == null) return null;
      if (!manual && !update.required && prefs.getString(_skipKey) == update.version) return null;
      return update;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!manual) {
      final last = prefs.getInt(_checkedKey) ?? 0;
      if (now - last < const Duration(hours: 6).inMilliseconds) {
        // Between checks a required update is still shown every time, from what was saved.
        final saved = _savedRequired(prefs);
        return saved != null && AppUpdate.compareVersions(saved.version, kVersionName) > 0 ? saved : null;
      }
    }
    try {
      final res = await _client
          .get(Uri.parse(kLatestReleaseApi), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('GitHub returned ${res.statusCode}');
      await prefs.setInt(_checkedKey, now);
      final update = AppUpdate.fromRelease(Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map));
      if (update?.required ?? false) {
        await prefs.setString(_requiredKey, jsonEncode(update!.toJson()));
      } else {
        await prefs.remove(_requiredKey);
      }
      if (update == null) return null;
      if (!manual && !update.required && prefs.getString(_skipKey) == update.version) return null;
      return update;
    } catch (_) {
      if (manual) rethrow;
      // Offline: a required update seen before still has to be installed.
      final saved = _savedRequired(prefs);
      return saved != null && AppUpdate.compareVersions(saved.version, kVersionName) > 0 ? saved : null;
    }
  }

  static const _requiredKey = 'update_required';

  AppUpdate? _savedRequired(SharedPreferences prefs) {
    try {
      return AppUpdate.fromJson(jsonDecode(prefs.getString(_requiredKey) ?? 'null'));
    } catch (_) {
      return null;
    }
  }

  Future<void> skip(String version) async => (await SharedPreferences.getInstance()).setString(_skipKey, version);
}
