import 'dart:math' as math;

import 'track.dart';

/// Forgiving text matching for search: typos, partial words and the many ways
/// Hindi/Bengali titles get spelt in English ("chaleya" / "chaliya",
/// "phir" / "fir", "tumhi ho" / "tum hi ho").
class Fuzzy {
  static final _nonWord = RegExp(r'[^a-z0-9 ]+');
  static final _spaces = RegExp(r'\s+');

  /// Lowercase words with punctuation removed.
  static List<String> words(String s) =>
      s.toLowerCase().replaceAll(_nonWord, ' ').trim().split(_spaces).where((w) => w.isNotEmpty).toList();

  /// Folds spelling variants of a word to one sound-alike key.
  static String phonetic(String w) {
    var s = w
        .replaceAll('ph', 'f')
        .replaceAll('kh', 'k')
        .replaceAll('gh', 'g')
        .replaceAll('chh', 'c')
        .replaceAll('ch', 'c')
        .replaceAll('sh', 's')
        .replaceAll('th', 't')
        .replaceAll('dh', 'd')
        .replaceAll('bh', 'b')
        .replaceAll('ck', 'k')
        .replaceAll('ee', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('w', 'v')
        .replaceAll('z', 'j')
        .replaceAll('q', 'k')
        .replaceAll('y', 'i');
    // Collapse doubled letters ("challiya" -> "calia").
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i == 0 || s[i] != s[i - 1]) b.write(s[i]);
    }
    s = b.toString();
    return s.length > 1 && s.endsWith('h') ? s.substring(0, s.length - 1) : s;
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// 0..1: how alike one typed word is to one word of a title.
  static double wordSimilarity(String typed, String target) {
    if (typed == target) return 1;
    final a = phonetic(typed), b = phonetic(target);
    if (a == b) return 0.95;
    // Partly typed word: "kesar" -> "kesariya".
    if (a.length >= 3 && b.startsWith(a)) return 0.9;
    final len = math.max(a.length, b.length);
    final s = 1 - _lev(a, b) / len;
    return s < 0.5 ? 0 : s;
  }

  /// 0..1: how well [query] matches [text], word by word (order-free).
  static double score(String query, String text) {
    final q = words(query);
    final t = words(text);
    if (q.isEmpty || t.isEmpty) return 0;
    var total = 0.0, weight = 0.0;
    for (final w in q) {
      var best = 0.0;
      for (final x in t) {
        final s = wordSimilarity(w, x);
        if (s > best) best = s;
        if (best == 1) break;
      }
      final wt = math.max(2, w.length).toDouble(); // long words matter more than "ho"/"se"
      total += best * wt;
      weight += wt;
    }
    var s = total / weight;
    // Spacing mistakes: "tumhi ho" vs "Tum Hi Ho".
    final qj = phonetic(q.join()), tj = phonetic(t.join());
    if (qj.length >= 4 && tj.contains(qj)) s = math.max(s, 0.95);
    return s;
  }

  /// How well a song matches what was typed. The title counts most; artist
  /// and album names help when the listener typed them too.
  static double songScore(String query, Track t) {
    final title = score(query, t.title);
    final all = score(query, '${t.title} ${t.artists.map((a) => a.name).join(' ')} ${t.album}');
    return math.max(title, all * 0.92);
  }

  /// Alternative queries to try when [query] finds little: the query with one
  /// word left out (so one badly misspelt word can't sink the whole search).
  static List<String> dropOneWord(String query) {
    final w = query.trim().split(_spaces).where((x) => x.isNotEmpty).toList();
    if (w.length < 2 || w.length > 6) return const [];
    return [
      for (var i = 0; i < w.length; i++) [...w.sublist(0, i), ...w.sublist(i + 1)].join(' '),
    ];
  }
}
