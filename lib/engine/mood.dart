import '../data/track.dart';

/// How a song feels. Used to tint the whole app.
///
/// There's no audio analysis on the device, so the mood is *inferred* from what
/// we do know: words in the title / album (English plus Hindi and Bengali
/// transliterations), the category the listener started from, and the era.
enum Mood { romantic, sad, party, chill, devotional, nostalgic, focus }

class MoodDetector {
  static const _words = <Mood, List<String>>{
    Mood.sad: [
      'sad', 'dard', 'judai', 'bewafa', 'bewafaa', 'alvida', 'tanha', 'tanhai', 'dukh', 'heartbreak', 'broken', 'tears',
      'aansu', 'rula', 'rona', 'kanna', 'birohe', 'biroho', 'bedona', 'bichhed', 'virah', 'gham', 'toota', 'lonely',
      'goodbye', 'bekhayali', 'hurt', 'cry', 'yaad', 'yaadein', 'intezaar', 'khamoshi',
    ],
    Mood.romantic: [
      'love', 'pyar', 'pyaar', 'ishq', 'ishk', 'mohabbat', 'muhabbat', 'dil', 'prem', 'bhalobasa', 'bhalobashi', 'valobasa',
      'romantic', 'sanam', 'jaan', 'sajna', 'saajan', 'mehboob', 'kiss', 'rooh', 'humsafar', 'raataan', 'hamesha', 'tum hi',
      'tera ban', 'ami tomake', 'kabhi kabhie', 'kabhi kabhi', 'romance', 'valentine',
    ],
    Mood.party: [
      'party', 'dance', 'dj', 'remix', 'nachle', 'nachde', 'dhol', 'beat', 'club', 'masti', 'disco', 'bass', 'garba',
      'dandiya', 'bhangra', 'swag', 'kala chashma', 'dhamaka', 'workout', 'gym',
    ],
    Mood.chill: [
      'lofi', 'lo-fi', 'chill', 'slowed', 'reverb', 'acoustic', 'unplugged', 'relax', 'sleep', 'calm', 'night drive',
      'barsaat', 'rain', 'drive', 'cafe', 'feel good', 'road trip',
    ],
    Mood.devotional: [
      'bhajan', 'aarti', 'arti', 'hanuman', 'krishna', 'radha', 'ram', 'shiv', 'shiva', 'om', 'mantra', 'durga', 'kali',
      'stotram', 'stotra', 'kirtan', 'ganesh', 'gayatri', 'chalisa', 'allah', 'qawwali', 'naat', 'jai', 'saraswati',
      'lakshmi', 'hare', 'bhakti', 'devotional', 'sufi', 'shyam', 'sai',
    ],
    Mood.nostalgic: [
      'evergreen', 'retro', 'classic', 'golden', 'old is gold', '60s', '70s', '80s', 'rabindra', 'nazrul', 'ghazal',
      'nostalgia', 'purane', 'geeti',
    ],
    Mood.focus: ['instrumental', 'flute', 'sitar', 'santoor', 'raga', 'raag', 'study', 'focus', 'meditation', 'piano'],
  };

  /// A safe tie-break order (earlier wins).
  static const _priority = [Mood.devotional, Mood.sad, Mood.romantic, Mood.party, Mood.chill, Mood.focus, Mood.nostalgic];

  static Set<String> _tokens(String s) => s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toSet();

  static double _score(Mood m, String text, Set<String> tokens) {
    var s = 0.0;
    for (final w in _words[m]!) {
      final multi = w.contains(' ') || w.contains('-');
      if (multi ? text.contains(w) : tokens.contains(w)) s += 1;
    }
    return s;
  }

  /// The mood of [t], or null when nothing points anywhere (the app then keeps
  /// its default colours and just follows the album art).
  static Mood? detect(Track t, {String? context}) {
    final own = '${t.title} ${t.album}'.toLowerCase();
    final ctx = (context ?? '').toLowerCase();
    final ownTokens = _tokens(own);
    final ctxTokens = _tokens(ctx);

    final scores = <Mood, double>{};
    for (final m in Mood.values) {
      // The song's own words count most; the category you came from counts too.
      final v = _score(m, own, ownTokens) * 2 + _score(m, ctx, ctxTokens) * 1.4;
      if (v > 0) scores[m] = v;
    }
    // Older songs lean nostalgic unless something stronger says otherwise.
    if (t.year > 0 && t.year <= 1985) scores[Mood.nostalgic] = (scores[Mood.nostalgic] ?? 0) + 1.5;

    if (scores.isEmpty) return null;
    Mood? best;
    var bestScore = 0.0;
    for (final m in _priority) {
      final v = scores[m];
      if (v != null && v > bestScore) {
        best = m;
        bestScore = v;
      }
    }
    return best;
  }
}
