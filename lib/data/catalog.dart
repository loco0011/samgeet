import 'package:flutter/material.dart';

/// A browsable tile: a mood, an era, a language, a genre...
class Category {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;

  /// Search phrase used to find curated playlists and songs.
  final String query;

  /// Extra phrase to widen the song list (optional).
  final String? songQuery;

  /// Language for the radio seed (defaults to hindi).
  final String language;

  const Category({
    required this.id,
    required this.title,
    required this.query,
    required this.icon,
    required this.colors,
    this.subtitle = '',
    this.songQuery,
    this.language = 'hindi',
  });
}

class CatalogGroup {
  final String id;
  final String title;
  final String subtitle;
  final List<Category> items;
  const CatalogGroup(this.id, this.title, this.subtitle, this.items);
}

class ArtistGroup {
  final String title;
  final List<String> names;
  const ArtistGroup(this.title, this.names);
}

class Catalog {
  // ---- moods ----
  static const chill = Category(
      id: 'chill', title: 'Chill', query: 'chill', songQuery: 'chill hindi songs', icon: Icons.spa_rounded, colors: [Color(0xFF00C9A7), Color(0xFF0072FF)]);
  static const romantic = Category(
      id: 'romantic', title: 'Romantic', query: 'romantic', songQuery: 'romantic hits', icon: Icons.favorite_rounded, colors: [Color(0xFFFF5F6D), Color(0xFFFFC371)]);
  static const sad = Category(
      id: 'sad', title: 'Heartbreak', query: 'sad songs', songQuery: 'sad heartbreak songs', icon: Icons.heart_broken_rounded, colors: [Color(0xFF485563), Color(0xFF29323C)]);
  static const party = Category(
      id: 'party', title: 'Party', query: 'party', songQuery: 'party dance hits', icon: Icons.celebration_rounded, colors: [Color(0xFFF953C6), Color(0xFFB91D73)]);
  static const workout = Category(
      id: 'workout', title: 'Workout', query: 'workout gym', songQuery: 'gym workout motivation', icon: Icons.fitness_center_rounded, colors: [Color(0xFFFF512F), Color(0xFFDD2476)]);
  static const focus = Category(
      id: 'focus', title: 'Focus', query: 'focus study instrumental', icon: Icons.psychology_rounded, colors: [Color(0xFF396AFC), Color(0xFF2948FF)]);
  static const sleep = Category(
      id: 'sleep', title: 'Sleep', query: 'sleep', songQuery: 'sleep relaxing music', icon: Icons.bedtime_rounded, colors: [Color(0xFF41295A), Color(0xFF2F0743)]);
  static const happy = Category(
      id: 'happy', title: 'Feel good', query: 'feel good happy', songQuery: 'happy feel good songs', icon: Icons.wb_sunny_rounded, colors: [Color(0xFFF7971E), Color(0xFFFFD200)]);
  static const devotional = Category(
      id: 'devotional', title: 'Devotional', query: 'bhakti devotional', icon: Icons.self_improvement_rounded, colors: [Color(0xFFFF9966), Color(0xFFFF5E62)]);
  static const roadtrip = Category(
      id: 'roadtrip', title: 'Road trip', query: 'road trip', songQuery: 'travel road trip songs', icon: Icons.directions_car_rounded, colors: [Color(0xFF11998E), Color(0xFF38EF7D)]);
  static const rain = Category(
      id: 'rain', title: 'Rainy day', query: 'rain songs', songQuery: 'barsaat rain songs', icon: Icons.water_drop_rounded, colors: [Color(0xFF4CA1AF), Color(0xFF2C3E50)]);
  static const lateNight = Category(
      id: 'latenight', title: 'Late night', query: 'late night', songQuery: 'late night drive songs', icon: Icons.nightlight_round, colors: [Color(0xFF0F2027), Color(0xFF2C5364)]);
  static const nostalgia = Category(
      id: 'nostalgia', title: 'Nostalgia', query: 'evergreen', songQuery: 'evergreen old is gold', icon: Icons.hourglass_bottom_rounded, colors: [Color(0xFFB79891), Color(0xFF94716B)]);
  static const lofi = Category(
      id: 'lofi', title: 'Lo-fi', query: 'lofi', songQuery: 'lofi hindi', icon: Icons.headphones_rounded, colors: [Color(0xFF8E9EAB), Color(0xFF536976)]);

  // ---- eras ----
  static const era70 = Category(
      id: 'era70', title: "70s", subtitle: 'Disco & drama', query: '70s bollywood', songQuery: '70s bollywood hits', icon: Icons.album_rounded, colors: [Color(0xFFDA4453), Color(0xFF89216B)]);
  static const era80 = Category(
      id: 'era80', title: "80s", subtitle: 'Golden melodies', query: '80s bollywood', songQuery: '80s bollywood hits', icon: Icons.album_rounded, colors: [Color(0xFFF2994A), Color(0xFFF2C94C)]);
  static const era90 = Category(
      id: 'era90', title: "90s", subtitle: 'The romance era', query: '90s bollywood', songQuery: '90s bollywood hits', icon: Icons.album_rounded, colors: [Color(0xFF7F00FF), Color(0xFFE100FF)]);
  static const era00 = Category(
      id: 'era00', title: "2000s", subtitle: 'Y2K nostalgia', query: '2000s bollywood', songQuery: '2000s bollywood hits', icon: Icons.album_rounded, colors: [Color(0xFF00B4DB), Color(0xFF0083B0)]);
  static const era10 = Category(
      id: 'era10', title: "2010s", subtitle: 'Modern classics', query: '2010s bollywood', songQuery: '2010s bollywood hits', icon: Icons.album_rounded, colors: [Color(0xFF56AB2F), Color(0xFFA8E063)]);
  static const golden = Category(
      id: 'golden', title: 'Golden era', subtitle: '50s & 60s classics', query: 'old hindi classics', songQuery: 'kishore kumar lata mangeshkar rafi evergreen', icon: Icons.stars_rounded, colors: [Color(0xFFBF953F), Color(0xFF8E6B1F)]);
  static const latest = Category(
      id: 'latest', title: 'Latest hits', subtitle: 'Fresh this week', query: 'latest hindi songs', songQuery: 'new hindi songs', icon: Icons.bolt_rounded, colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)]);
  static const trending = Category(
      id: 'trending', title: 'Trending now', subtitle: 'Everyone is playing', query: 'trending', songQuery: 'trending songs', icon: Icons.trending_up_rounded, colors: [Color(0xFFFC466B), Color(0xFF3F5EFB)]);

  // ---- Indian languages ----
  static const bengali = Category(
      id: 'bengali', title: 'Bengali', subtitle: 'বাংলা গান', query: 'bengali hits', songQuery: 'bengali songs', language: 'bengali', icon: Icons.music_note_rounded, colors: [Color(0xFFE53935), Color(0xFFFF8A65)]);
  static const hindi = Category(
      id: 'hindi', title: 'Hindi', subtitle: 'हिन्दी', query: 'hindi hits', songQuery: 'hindi songs', icon: Icons.music_note_rounded, colors: [Color(0xFFFF7A18), Color(0xFFAF002D)]);
  static const punjabi = Category(
      id: 'punjabi', title: 'Punjabi', subtitle: 'ਪੰਜਾਬੀ', query: 'punjabi hits', songQuery: 'punjabi songs', language: 'punjabi', icon: Icons.music_note_rounded, colors: [Color(0xFF00C853), Color(0xFF64DD17)]);
  static const tamil = Category(
      id: 'tamil', title: 'Tamil', subtitle: 'தமிழ்', query: 'tamil hits', songQuery: 'tamil songs', language: 'tamil', icon: Icons.music_note_rounded, colors: [Color(0xFF2196F3), Color(0xFF00BCD4)]);
  static const telugu = Category(
      id: 'telugu', title: 'Telugu', subtitle: 'తెలుగు', query: 'telugu hits', songQuery: 'telugu songs', language: 'telugu', icon: Icons.music_note_rounded, colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)]);
  static const malayalam = Category(
      id: 'malayalam', title: 'Malayalam', subtitle: 'മലയാളം', query: 'malayalam hits', songQuery: 'malayalam songs', language: 'malayalam', icon: Icons.music_note_rounded, colors: [Color(0xFF009688), Color(0xFF4DB6AC)]);
  static const kannada = Category(
      id: 'kannada', title: 'Kannada', subtitle: 'ಕನ್ನಡ', query: 'kannada hits', songQuery: 'kannada songs', language: 'kannada', icon: Icons.music_note_rounded, colors: [Color(0xFFFFB300), Color(0xFFFF6F00)]);
  static const marathi = Category(
      id: 'marathi', title: 'Marathi', subtitle: 'मराठी', query: 'marathi hits', songQuery: 'marathi songs', language: 'marathi', icon: Icons.music_note_rounded, colors: [Color(0xFFEC407A), Color(0xFFAB47BC)]);
  static const gujarati = Category(
      id: 'gujarati', title: 'Gujarati', subtitle: 'ગુજરાતી', query: 'gujarati hits', songQuery: 'gujarati songs', language: 'gujarati', icon: Icons.music_note_rounded, colors: [Color(0xFFFF7043), Color(0xFFFFCA28)]);
  static const bhojpuri = Category(
      id: 'bhojpuri', title: 'Bhojpuri', subtitle: 'भोजपुरी', query: 'bhojpuri hits', songQuery: 'bhojpuri songs', language: 'bhojpuri', icon: Icons.music_note_rounded, colors: [Color(0xFF6D4C41), Color(0xFFFF8F00)]);
  static const odia = Category(
      id: 'odia', title: 'Odia', subtitle: 'ଓଡ଼ିଆ', query: 'odia hits', songQuery: 'odia songs', language: 'odia', icon: Icons.music_note_rounded, colors: [Color(0xFF26A69A), Color(0xFF1565C0)]);
  static const assamese = Category(
      id: 'assamese', title: 'Assamese', subtitle: 'অসমীয়া', query: 'assamese hits', songQuery: 'assamese songs', language: 'assamese', icon: Icons.music_note_rounded, colors: [Color(0xFF43A047), Color(0xFF1B5E20)]);
  static const haryanvi = Category(
      id: 'haryanvi', title: 'Haryanvi', subtitle: 'हरियाणवी', query: 'haryanvi hits', songQuery: 'haryanvi songs', language: 'haryanvi', icon: Icons.music_note_rounded, colors: [Color(0xFFD84315), Color(0xFFFF7043)]);

  // ---- Bengali special ----
  static const rabindra = Category(
      id: 'rabindra', title: 'Rabindra Sangeet', subtitle: 'Tagore', query: 'rabindra sangeet', songQuery: 'rabindra sangeet', language: 'bengali', icon: Icons.local_florist_rounded, colors: [Color(0xFF3A6186), Color(0xFF89253E)]);
  static const nazrul = Category(
      id: 'nazrul', title: 'Nazrul Geeti', subtitle: 'Kazi Nazrul Islam', query: 'nazrul geeti', songQuery: 'nazrul geeti', language: 'bengali', icon: Icons.local_florist_rounded, colors: [Color(0xFF134E5E), Color(0xFF71B280)]);
  static const bengaliOld = Category(
      id: 'bengali_old', title: 'Old Bengali', subtitle: 'Hemanta • Manna Dey • Kishore', query: 'old bengali', songQuery: 'hemanta mukherjee manna dey bengali', language: 'bengali', icon: Icons.album_rounded, colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]);
  static const bengaliAdhunik = Category(
      id: 'bengali_adhunik', title: 'Adhunik', subtitle: 'Modern Bengali', query: 'bengali adhunik', songQuery: 'bengali adhunik gaan', language: 'bengali', icon: Icons.graphic_eq_rounded, colors: [Color(0xFFFF512F), Color(0xFFF09819)]);
  static const bengaliBand = Category(
      id: 'bengali_band', title: 'Bangla Band', subtitle: 'Fossils • Cactus • Bhoomi', query: 'bengali band songs', songQuery: 'bangla band', language: 'bengali', icon: Icons.mic_external_on_rounded, colors: [Color(0xFF232526), Color(0xFF414345)]);
  static const bengaliFilm = Category(
      id: 'bengali_film', title: 'Bengali Cinema', subtitle: 'Tollywood hits', query: 'bengali film hits', songQuery: 'bengali movie songs', language: 'bengali', icon: Icons.movie_rounded, colors: [Color(0xFFCB356B), Color(0xFFBD3F32)]);
  static const baul = Category(
      id: 'baul', title: 'Baul & Folk', subtitle: 'Lokgeeti', query: 'baul', songQuery: 'baul gaan', language: 'bengali', icon: Icons.landscape_rounded, colors: [Color(0xFFB24592), Color(0xFFF15F79)]);

  // ---- Classical & traditional ----
  static const hindustani = Category(
      id: 'hindustani', title: 'Hindustani', subtitle: 'Classical', query: 'hindustani classical', songQuery: 'hindustani classical vocal', icon: Icons.piano_rounded, colors: [Color(0xFF614385), Color(0xFF516395)]);
  static const carnatic = Category(
      id: 'carnatic', title: 'Carnatic', subtitle: 'South classical', query: 'carnatic', songQuery: 'carnatic classical songs', language: 'tamil', icon: Icons.piano_rounded, colors: [Color(0xFF0F9B0F), Color(0xFF000000)]);
  static const ghazal = Category(
      id: 'ghazal', title: 'Ghazals', subtitle: 'Jagjit • Ghulam Ali • Mehdi Hassan', query: 'ghazal', songQuery: 'ghazal jagjit singh ghulam ali', icon: Icons.nights_stay_rounded, colors: [Color(0xFF283048), Color(0xFF859398)]);
  static const sufi = Category(
      id: 'sufi', title: 'Sufi & Qawwali', subtitle: 'Soulful', query: 'sufi qawwali', songQuery: 'sufi songs', icon: Icons.auto_awesome_rounded, colors: [Color(0xFF3D7EAA), Color(0xFFFFE47A)]);
  static const instrumental = Category(
      id: 'instrumental', title: 'Instrumental', subtitle: 'Sitar • Flute • Santoor', query: 'instrumental', songQuery: 'sitar flute instrumental', icon: Icons.music_note_outlined, colors: [Color(0xFF16A085), Color(0xFFF4D03F)]);

  // ---- genres ----
  static const pop = Category(
      id: 'pop', title: 'Pop', query: 'pop hits', songQuery: 'top pop songs', icon: Icons.star_rounded, colors: [Color(0xFFFF6FD8), Color(0xFF3813C2)]);
  static const rock = Category(
      id: 'rock', title: 'Rock', query: 'rock', songQuery: 'indian rock', icon: Icons.electric_bolt_rounded, colors: [Color(0xFF434343), Color(0xFF000000)]);
  static const hiphop = Category(
      id: 'hiphop', title: 'Hip-Hop', query: 'hip hop rap', songQuery: 'desi hip hop', icon: Icons.mic_rounded, colors: [Color(0xFFFDC830), Color(0xFFF37335)]);
  static const edm = Category(
      id: 'edm', title: 'EDM', query: 'edm dance', songQuery: 'edm electronic', icon: Icons.equalizer_rounded, colors: [Color(0xFF8A2BE2), Color(0xFF00E5FF)]);
  static const indie = Category(
      id: 'indie', title: 'Indie', query: 'indie', songQuery: 'indian indie', icon: Icons.brush_rounded, colors: [Color(0xFF00CDAC), Color(0xFF8DDAD5)]);
  static const acoustic = Category(
      id: 'acoustic', title: 'Acoustic', query: 'acoustic unplugged', songQuery: 'unplugged acoustic', icon: Icons.piano_rounded, colors: [Color(0xFFD38312), Color(0xFFA83279)]);
  static const jazz = Category(
      id: 'jazz', title: 'Jazz & Blues', query: 'jazz', songQuery: 'jazz', language: 'english', icon: Icons.airline_seat_recline_extra_rounded, colors: [Color(0xFF373B44), Color(0xFF4286F4)]);

  // ---- world ----
  static const english = Category(
      id: 'english', title: 'English Pop', subtitle: 'Global hits', query: 'english hits', songQuery: 'english pop hits', language: 'english', icon: Icons.public_rounded, colors: [Color(0xFF1D976C), Color(0xFF93F9B9)]);
  static const kpop = Category(
      id: 'kpop', title: 'K-Pop', subtitle: 'Korea', query: 'k-pop', songQuery: 'kpop hits', language: 'korean', icon: Icons.public_rounded, colors: [Color(0xFFFF9A9E), Color(0xFFA18CD1)]);
  static const latin = Category(
      id: 'latin', title: 'Latin', subtitle: 'Reggaeton • Salsa', query: 'latin', songQuery: 'latin reggaeton hits', language: 'spanish', icon: Icons.public_rounded, colors: [Color(0xFFFF512F), Color(0xFFDD2476)]);
  static const arabic = Category(
      id: 'arabic', title: 'Arabic', subtitle: 'Middle East', query: 'arabic', songQuery: 'arabic songs', language: 'arabic', icon: Icons.public_rounded, colors: [Color(0xFFC79081), Color(0xFFDFA579)]);
  static const jpop = Category(
      id: 'jpop', title: 'J-Pop & Anime', subtitle: 'Japan', query: 'anime j-pop', songQuery: 'anime songs', language: 'japanese', icon: Icons.public_rounded, colors: [Color(0xFFEE9CA7), Color(0xFFFFDDE1)]);
  static const afro = Category(
      id: 'afro', title: 'Afrobeats', subtitle: 'Africa', query: 'afrobeats', songQuery: 'afrobeats hits', language: 'english', icon: Icons.public_rounded, colors: [Color(0xFF11998E), Color(0xFFFFD200)]);

  static const groups = <CatalogGroup>[
    CatalogGroup('mood', 'Moods', 'Music for how you feel',
        [chill, romantic, sad, party, workout, focus, sleep, happy, devotional, roadtrip, rain, lateNight, nostalgia, lofi]),
    CatalogGroup('era', 'Time machine', 'Journey through the decades',
        [trending, latest, era10, era00, era90, era80, era70, golden]),
    CatalogGroup('bengali', 'Bengali corner', 'বাংলা সঙ্গীত',
        [bengali, rabindra, nazrul, bengaliOld, bengaliAdhunik, bengaliBand, bengaliFilm, baul]),
    CatalogGroup('india', 'Indian languages', 'Music from across India',
        [hindi, punjabi, tamil, telugu, malayalam, kannada, marathi, gujarati, bhojpuri, odia, assamese, haryanvi]),
    CatalogGroup('classical', 'Classical & traditional', 'Timeless forms',
        [hindustani, carnatic, ghazal, sufi, instrumental, devotional]),
    CatalogGroup('genre', 'Genres', 'Pick your sound', [pop, rock, hiphop, edm, indie, acoustic, jazz, lofi]),
    CatalogGroup('world', 'Around the world', 'Sounds from everywhere', [english, kpop, latin, arabic, jpop, afro]),
  ];

  static final Map<String, Category> byId = {
    for (final g in groups)
      for (final c in g.items) c.id: c,
  };

  /// Favourite singers, grouped. Resolved to real artist pages on demand.
  static const artistGroups = <ArtistGroup>[
    ArtistGroup('Bollywood legends', [
      'Kishore Kumar', 'Lata Mangeshkar', 'Mohammed Rafi', 'Asha Bhosle', 'Mukesh', 'Kumar Sanu', 'Udit Narayan', 'Alka Yagnik',
    ]),
    ArtistGroup('Bengali favourites', [
      'Hemanta Mukherjee', 'Manna Dey', 'Anupam Roy', 'Nachiketa', 'Kabir Suman', 'Lopamudra Mitra', 'Rupam Islam', 'Arijit Singh',
    ]),
    ArtistGroup("Today's voices", [
      'Arijit Singh', 'Shreya Ghoshal', 'Sonu Nigam', 'KK', 'A.R. Rahman', 'Atif Aslam', 'Jubin Nautiyal', 'Sid Sriram', 'Diljit Dosanjh', 'Badshah',
    ]),
    ArtistGroup('Global stars', [
      'Taylor Swift', 'The Weeknd', 'Ed Sheeran', 'Dua Lipa', 'Coldplay', 'BTS', 'Bruno Mars', 'Billie Eilish',
    ]),
  ];

  /// Suggestions matched to the time of day.
  static List<Category> forHour(int hour) {
    if (hour >= 5 && hour < 11) return [devotional, happy, focus, latest];
    if (hour >= 11 && hour < 16) return [pop, workout, focus, trending];
    if (hour >= 16 && hour < 21) return [romantic, roadtrip, party, chill];
    return [lateNight, chill, sad, sleep];
  }

  static String greeting(int hour) {
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 17) return 'Good afternoon';
    if (hour >= 17 && hour < 22) return 'Good evening';
    return 'Night owl';
  }

  /// Ordered so the chips pack into as few wrapped rows as possible (short
  /// names paired with long ones): 4 · 4 · 3 · 3.
  static const languageChoices = <String, String>{
    'hindi': 'Hindi',
    'bengali': 'Bengali',
    'english': 'English',
    'punjabi': 'Punjabi',
    'tamil': 'Tamil',
    'telugu': 'Telugu',
    'odia': 'Odia',
    'kannada': 'Kannada',
    'malayalam': 'Malayalam',
    'marathi': 'Marathi',
    'gujarati': 'Gujarati',
    'bhojpuri': 'Bhojpuri',
    'assamese': 'Assamese',
    'haryanvi': 'Haryanvi',
  };
}
