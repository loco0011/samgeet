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

  /// Hand-picked songs (search phrases) shown first, before the search results.
  final List<String> picks;

  /// More song searches (singers, sub-styles) mixed into the list to widen it.
  final List<String> moreQueries;

  /// Keep only songs in [language]. For styles whose search words also match
  /// titles in other languages (an English "Ballad" next to a Korean ballad).
  final bool strictLanguage;

  /// Whether to look for curated playlists (off where that search finds junk).
  final bool playlists;

  const Category({
    required this.id,
    required this.title,
    required this.query,
    required this.icon,
    required this.colors,
    this.subtitle = '',
    this.songQuery,
    this.language = 'hindi',
    this.picks = const [],
    this.moreQueries = const [],
    this.strictLanguage = false,
    this.playlists = true,
  });

  /// Every song search this tile runs, main one first.
  List<String> get songQueries => [songQuery ?? query, ...moreQueries];
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

  // ---- festivals ----
  static const durgaPuja = Category(
      id: 'durga_puja', title: 'Durga Puja', subtitle: 'Pujo hits · দুর্গাপুজো', query: 'durga puja', songQuery: 'durga puja songs', language: 'bengali',
      icon: Icons.festival_rounded, colors: [Color(0xFFD50000), Color(0xFFFFAB00)],
      picks: [
        'Dhak Baja Kashor Baja Shreya Ghoshal', 'Dugga Elo Monali Thakur', 'Bolo Dugga Maiki Nakash Aziz', 'Dugga Ma Arijit Singh',
        'Aami Shotti Bolchi', 'Durge Durge Durgatinashini Asha Bhosle', 'Elo Re Elo Durga Maa', 'Ebar Aamar Uma Eley',
        'Pujo Pujo Gondho Anupam Roy', 'Dhunuchi Nach', 'Pujor Dhaak Bickram Ghosh', 'Jai Maa Durga', 'Pujor Gaan Mita Chatterjee',
      ]);
  static const mahalaya = Category(
      id: 'mahalaya', title: 'Mahalaya', subtitle: 'Mahishasura Mardini · stotras', query: 'mahalaya', songQuery: 'mahishasura mardini', language: 'bengali',
      icon: Icons.brightness_7_rounded, colors: [Color(0xFFFF6F00), Color(0xFF6A1B9A)],
      picks: [
        'Jago Durga Dashapraharanadharinee', 'Jago Durga Manohar Ghosal', 'Bajlo Tomar Alor Benu', 'Ya Devi Sarvabhuteshu',
        'Aigiri Nandini', 'Maa Durga Aarti Shoma Banerjee', 'Durga Chalisa',
      ]);

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
  static const hindustaniVocal = Category(
      id: 'hindustani_vocal', title: 'Khayal vocal', subtitle: 'Bhimsen Joshi • Kishori Amonkar', query: 'hindustani classical', songQuery: 'hindustani classical vocal raga',
      moreQueries: ['bhimsen joshi raga', 'kishori amonkar', 'pandit jasraj', 'kumar gandharva', 'rashid khan raga'], icon: Icons.record_voice_over_rounded, colors: [Color(0xFF4B134F), Color(0xFFC94B4B)]);
  static const sitar = Category(
      id: 'sitar', title: 'Sitar', subtitle: 'Ravi Shankar • Vilayat Khan', query: 'classical instrumental', songQuery: 'sitar ravi shankar', playlists: false,
      moreQueries: ['sitar raga', 'vilayat khan sitar', 'anoushka shankar', 'nikhil banerjee sitar'], icon: Icons.music_note_rounded, colors: [Color(0xFFB06AB3), Color(0xFF4568DC)]);
  static const bansuri = Category(
      id: 'bansuri', title: 'Bansuri', subtitle: 'Hariprasad Chaurasia', query: 'flute instrumental', songQuery: 'hariprasad chaurasia flute',
      moreQueries: ['bansuri raga', 'flute raga', 'ronu majumdar flute', 'rakesh chaurasia flute'], icon: Icons.air_rounded, colors: [Color(0xFF1FA2FF), Color(0xFF12D8FA)]);
  static const santoor = Category(
      id: 'santoor', title: 'Santoor & Sarod', subtitle: 'Shivkumar Sharma • Amjad Ali Khan', query: 'classical instrumental', songQuery: 'santoor shivkumar sharma', playlists: false,
      moreQueries: ['sarod amjad ali khan', 'santoor raga', 'sarod raga', 'rahul sharma santoor'], icon: Icons.grid_on_rounded, colors: [Color(0xFF0B486B), Color(0xFFF56217)]);
  static const shehnai = Category(
      id: 'shehnai', title: 'Shehnai & Tabla', subtitle: 'Bismillah Khan • Zakir Hussain', query: 'classical instrumental', songQuery: 'bismillah khan shehnai', playlists: false,
      moreQueries: ['tabla solo', 'zakir hussain tabla', 'shehnai raga', 'tabla teental'], icon: Icons.graphic_eq_rounded, colors: [Color(0xFF8E0E00), Color(0xFF1F1C18)]);
  static const thumri = Category(
      id: 'thumri', title: 'Thumri & Dadra', subtitle: 'Semi-classical', query: 'thumri', songQuery: 'thumri', playlists: false,
      moreQueries: ['dadra', 'girija devi thumri', 'begum akhtar', 'shobha gurtu'], icon: Icons.spa_outlined, colors: [Color(0xFFDD5E89), Color(0xFFF7BB97)]);
  static const dhrupad = Category(
      id: 'dhrupad', title: 'Dhrupad', subtitle: 'The oldest form', query: 'dhrupad', songQuery: 'dhrupad', playlists: false,
      moreQueries: ['gundecha brothers dhrupad', 'dagar dhrupad'], icon: Icons.account_balance_rounded, colors: [Color(0xFF3E5151), Color(0xFFDECBA4)]);
  static const ragas = Category(
      id: 'ragas', title: 'Ragas by the hour', subtitle: 'Morning • Evening • Night', query: 'morning ragas', songQuery: 'morning raga',
      moreQueries: ['raga bhairav', 'raga yaman', 'raga darbari', 'raga ahir bhairav', 'raga malkauns'], icon: Icons.wb_twilight_rounded, colors: [Color(0xFFF2994A), Color(0xFF6A3093)]);
  static const carnaticVocal = Category(
      id: 'carnatic_vocal', title: 'Carnatic vocal', subtitle: 'M.S. Subbulakshmi • Balamurali', query: 'carnatic vocal', songQuery: 'carnatic vocal', language: 'tamil',
      moreQueries: ['m s subbulakshmi', 'balamuralikrishna', 'bombay jayashri', 'sudha raghunathan', 'tm krishna'], icon: Icons.record_voice_over_rounded, colors: [Color(0xFF0F9B0F), Color(0xFFF7B733)]);
  static const veena = Category(
      id: 'veena', title: 'Veena & Violin', subtitle: 'South Indian strings', query: 'veena', songQuery: 'veena carnatic',
      moreQueries: ['carnatic violin', 'veena instrumental', 'mandolin srinivas', 'chitti babu veena'], icon: Icons.music_note_rounded, colors: [Color(0xFF136A8A), Color(0xFF267871)]);
  static const mantras = Category(
      id: 'mantras', title: 'Mantras & Stotras', subtitle: 'Sanskrit chants', query: 'mantra', songQuery: 'sanskrit mantra', language: 'sanskrit',
      moreQueries: ['sanskrit stotram', 'vedic chants'], icon: Icons.self_improvement_rounded, colors: [Color(0xFFFF8008), Color(0xFFFFC837)]);

  // ---- Korean ----
  static const kdrama = Category(
      id: 'kdrama', title: 'K-Drama OST', subtitle: 'Songs from the shows', query: 'k-pop', songQuery: 'korean drama ost', language: 'korean', strictLanguage: true, playlists: false,
      moreQueries: ['ost korean', 'drama ost korean'], icon: Icons.live_tv_rounded, colors: [Color(0xFFFFAFBD), Color(0xFFC9FFBF)]);
  static const kballad = Category(
      id: 'kballad', title: 'K-Ballad', subtitle: 'Slow & emotional', query: 'k-pop', songQuery: 'korean ballad', language: 'korean', strictLanguage: true, playlists: false,
      moreQueries: ['korean love songs', 'korean sad songs'], icon: Icons.favorite_rounded, colors: [Color(0xFF834D9B), Color(0xFFD04ED6)]);
  static const khiphop = Category(
      id: 'khiphop', title: 'K-Hip-Hop', subtitle: 'Seoul rap', query: 'k-pop', songQuery: 'korean hip hop', language: 'korean', strictLanguage: true, playlists: false,
      moreQueries: ['korean rap', 'jay park', 'epik high'], icon: Icons.mic_rounded, colors: [Color(0xFF000000), Color(0xFFE74C3C)]);
  static const krnb = Category(
      id: 'krnb', title: 'K-R&B & Indie', subtitle: 'Smooth and mellow', query: 'k-pop', songQuery: 'korean r&b', language: 'korean', strictLanguage: true, playlists: false,
      moreQueries: ['korean indie', 'korean acoustic'], icon: Icons.nightlife_rounded, colors: [Color(0xFF654EA3), Color(0xFFEAAFC8)]);
  static const kgirls = Category(
      id: 'kgirls', title: 'Girl groups', subtitle: 'BLACKPINK • aespa • NewJeans', query: 'k-pop', songQuery: 'BLACKPINK', language: 'korean', strictLanguage: true,
      moreQueries: ['aespa', 'NewJeans', 'LE SSERAFIM', 'ITZY', 'IVE korean'], icon: Icons.star_rounded, colors: [Color(0xFFFF6A88), Color(0xFFFF99AC)]);
  static const kboys = Category(
      id: 'kboys', title: 'Boy groups', subtitle: 'BTS • Stray Kids • SEVENTEEN', query: 'k-pop', songQuery: 'BTS', language: 'korean', strictLanguage: true,
      moreQueries: ['Stray Kids', 'Jimin', 'Jung Kook', 'SEVENTEEN korean', 'ATEEZ korean'], icon: Icons.groups_rounded, colors: [Color(0xFF4776E6), Color(0xFF8E54E9)]);
  static const trot = Category(
      id: 'trot', title: 'Trot', subtitle: 'Classic Korean pop', query: 'k-pop', songQuery: 'trot korean', language: 'korean', strictLanguage: true, playlists: false,
      icon: Icons.radio_rounded, colors: [Color(0xFFF7971E), Color(0xFFE44D26)]);

  // ---- More Indian languages ----
  static const urdu = Category(
      id: 'urdu', title: 'Urdu', subtitle: 'اردو', query: 'urdu', songQuery: 'urdu songs', language: 'urdu', strictLanguage: true, icon: Icons.music_note_rounded, colors: [Color(0xFF134E5E), Color(0xFF71B280)]);
  static const rajasthani = Category(
      id: 'rajasthani', title: 'Rajasthani', subtitle: 'राजस्थानी', query: 'rajasthani', songQuery: 'rajasthani songs', language: 'rajasthani', strictLanguage: true, icon: Icons.music_note_rounded, colors: [Color(0xFFF09819), Color(0xFFEDDE5D)]);
  static const nepali = Category(
      id: 'nepali', title: 'Nepali', subtitle: 'नेपाली', query: 'nepali', songQuery: 'nepali songs', language: 'nepali', strictLanguage: true, icon: Icons.music_note_rounded, colors: [Color(0xFFC31432), Color(0xFF240B36)]);
  static const garhwali = Category(
      id: 'garhwali', title: 'Pahadi', subtitle: 'Garhwali • Kumaoni • Himachali', query: 'pahadi', songQuery: 'garhwali songs', playlists: false,
      moreQueries: ['kumaoni songs', 'himachali songs'], icon: Icons.terrain_rounded, colors: [Color(0xFF3CA55C), Color(0xFFB5AC49)]);
  static const konkani = Category(
      id: 'konkani', title: 'Konkani & Tulu', subtitle: 'The coast', query: 'konkani', songQuery: 'konkani songs', playlists: false,
      moreQueries: ['tulu songs'], icon: Icons.beach_access_rounded, colors: [Color(0xFF02AAB0), Color(0xFF00CDAC)]);
  static const northeast = Category(
      id: 'northeast', title: 'North-East', subtitle: 'Manipuri • Khasi • Mizo', query: 'manipuri', songQuery: 'manipuri songs', playlists: false,
      moreQueries: ['khasi songs', 'mizo songs', 'nagamese songs', 'kokborok songs'], icon: Icons.forest_rounded, colors: [Color(0xFF56AB2F), Color(0xFF1D4350)]);
  static const dogri = Category(
      id: 'dogri', title: 'Dogri & Kashmiri', subtitle: 'Jammu & Kashmir', query: 'dogri', songQuery: 'dogri songs', playlists: false,
      moreQueries: ['kashmiri song'], icon: Icons.ac_unit_rounded, colors: [Color(0xFF83A4D4), Color(0xFFB6FBFF)]);
  static const sinhala = Category(
      id: 'sinhala', title: 'Sinhala', subtitle: 'Sri Lanka', query: 'sinhala', songQuery: 'sinhala songs', language: 'sinhalese', strictLanguage: true, playlists: false,
      moreQueries: ['sinhala new songs'], icon: Icons.music_note_rounded, colors: [Color(0xFF8E2DE2), Color(0xFFFFB75E)]);

  // ---- Folk ----
  static const rajasthaniFolk = Category(
      id: 'rajasthani_folk', title: 'Rajasthani folk', subtitle: 'Manganiyar • Langa', query: 'rajasthani', songQuery: 'folk songs rajasthani', language: 'rajasthani', strictLanguage: true,
      moreQueries: ['manganiyar', 'kesariya balam'], icon: Icons.landscape_rounded, colors: [Color(0xFFE65C00), Color(0xFFF9D423)]);
  static const punjabiFolk = Category(
      id: 'punjabi_folk', title: 'Punjabi folk', subtitle: 'Boliyan • Tappe', query: 'punjabi folk', songQuery: 'punjabi folk songs', language: 'punjabi',
      moreQueries: ['boliyan', 'gurdas maan'], icon: Icons.agriculture_rounded, colors: [Color(0xFFFDC830), Color(0xFF0B8793)]);
  static const bihu = Category(
      id: 'bihu', title: 'Bihu', subtitle: 'Assam', query: 'bihu', songQuery: 'bihu songs', language: 'assamese', icon: Icons.celebration_rounded, colors: [Color(0xFFD31027), Color(0xFFEA384D)]);
  static const garba = Category(
      id: 'garba', title: 'Garba & Dandiya', subtitle: 'Navratri nights', query: 'garba', songQuery: 'garba songs', language: 'gujarati',
      moreQueries: ['dandiya songs'], icon: Icons.festival_rounded, colors: [Color(0xFFFF0084), Color(0xFFFFB347)]);
  static const lavani = Category(
      id: 'lavani', title: 'Lavani & Koli', subtitle: 'Maharashtra', query: 'lavani', songQuery: 'lavani', language: 'marathi',
      moreQueries: ['koligeet'], icon: Icons.nightlife_rounded, colors: [Color(0xFFEC008C), Color(0xFFFC6767)]);
  static const cokeStudio = Category(
      id: 'coke_studio', title: 'Coke Studio', subtitle: 'Bharat • Bangla • Pakistan', query: 'coke studio', songQuery: 'coke studio',
      moreQueries: ['coke studio bharat', 'coke studio bangla', 'coke studio pakistan'], icon: Icons.mic_external_on_rounded, colors: [Color(0xFFE52D27), Color(0xFFB31217)]);

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
  static const rnb = Category(
      id: 'rnb', title: 'R&B & Soul', query: 'r&b', songQuery: 'r&b soul', language: 'english', moreQueries: ['soul music', 'neo soul'],
      icon: Icons.nightlife_rounded, colors: [Color(0xFF6A3093), Color(0xFFA044FF)]);
  static const metal = Category(
      id: 'metal', title: 'Metal', query: 'metal', songQuery: 'metal', language: 'english', moreQueries: ['heavy metal', 'metallica', 'linkin park'],
      icon: Icons.bolt_rounded, colors: [Color(0xFF232526), Color(0xFF8E0E00)]);
  static const country = Category(
      id: 'country', title: 'Country', query: 'country', songQuery: 'country music', language: 'english', moreQueries: ['country hits'],
      icon: Icons.agriculture_rounded, colors: [Color(0xFFC04848), Color(0xFF480048)]);
  static const reggae = Category(
      id: 'reggae', title: 'Reggae', query: 'reggae', songQuery: 'reggae', language: 'english', moreQueries: ['bob marley'],
      icon: Icons.wb_sunny_rounded, colors: [Color(0xFF009245), Color(0xFFFCEE21)]);
  static const blues = Category(
      id: 'blues', title: 'Blues', query: 'blues', songQuery: 'blues', language: 'english', moreQueries: ['b.b. king', 'delta blues'],
      icon: Icons.music_note_rounded, colors: [Color(0xFF2B5876), Color(0xFF4E4376)]);
  static const westernClassical = Category(
      id: 'western_classical', title: 'Western classical', subtitle: 'Mozart • Beethoven • Bach', query: 'classical music', songQuery: 'mozart', language: 'english',
      moreQueries: ['beethoven symphony', 'bach', 'chopin nocturne', 'vivaldi four seasons'], icon: Icons.piano_rounded, colors: [Color(0xFF5C258D), Color(0xFF4389A2)]);
  static const soundtracks = Category(
      id: 'soundtracks', title: 'Film scores', subtitle: 'Soundtracks & themes', query: 'soundtrack', songQuery: 'movie soundtrack score', playlists: false,
      moreQueries: ['hans zimmer', 'original score', 'background score'], icon: Icons.movie_filter_rounded, colors: [Color(0xFF000046), Color(0xFF1CB5E0)]);
  static const kids = Category(
      id: 'kids', title: 'Kids', subtitle: 'Rhymes & lullabies', query: 'kids', songQuery: 'kids nursery rhymes',
      moreQueries: ['hindi nursery rhymes', 'lullaby'], icon: Icons.child_care_rounded, colors: [Color(0xFFFFE259), Color(0xFFFFA751)]);

  // ---- world ----
  static const english = Category(
      id: 'english', title: 'English Pop', subtitle: 'Global hits', query: 'english hits', songQuery: 'english pop hits', language: 'english',
      moreQueries: ['english party songs', 'english pop songs', 'taylor swift', 'the weeknd', 'dua lipa', 'ed sheeran'], icon: Icons.public_rounded, colors: [Color(0xFF1D976C), Color(0xFF93F9B9)]);
  static const kpop = Category(
      id: 'kpop', title: 'K-Pop', subtitle: 'Korea', query: 'k-pop', songQuery: 'korean songs', language: 'korean', strictLanguage: true,
      moreQueries: ['kpop', 'BLACKPINK', 'BTS', 'aespa', 'Stray Kids'], icon: Icons.public_rounded, colors: [Color(0xFFFF9A9E), Color(0xFFA18CD1)]);
  static const latin = Category(
      id: 'latin', title: 'Latin', subtitle: 'Reggaeton • Salsa', query: 'latin', songQuery: 'latin reggaeton hits', language: 'spanish', icon: Icons.public_rounded, colors: [Color(0xFFFF512F), Color(0xFFDD2476)]);
  static const arabic = Category(
      id: 'arabic', title: 'Arabic', subtitle: 'Middle East', query: 'arabic', songQuery: 'arabic songs', language: 'arabic', icon: Icons.public_rounded, colors: [Color(0xFFC79081), Color(0xFFDFA579)]);
  static const jpop = Category(
      id: 'jpop', title: 'J-Pop & Anime', subtitle: 'Japan', query: 'anime j-pop', songQuery: 'anime songs', language: 'japanese', icon: Icons.public_rounded, colors: [Color(0xFFEE9CA7), Color(0xFFFFDDE1)]);
  static const afro = Category(
      id: 'afro', title: 'Afrobeats', subtitle: 'Africa', query: 'afrobeats', songQuery: 'afrobeats hits', language: 'english', icon: Icons.public_rounded, colors: [Color(0xFF11998E), Color(0xFFFFD200)]);
  static const spanish = Category(
      id: 'spanish', title: 'Spanish', subtitle: 'Español', query: 'spanish', songQuery: 'spanish pop', language: 'spanish', strictLanguage: true,
      moreQueries: ['canciones en español', 'spanish love songs', 'reggaeton', 'bachata'], icon: Icons.public_rounded, colors: [Color(0xFFF12711), Color(0xFFF5AF19)]);
  static const french = Category(
      id: 'french', title: 'French', subtitle: 'Français', query: 'french', songQuery: 'french songs', language: 'french', strictLanguage: true, playlists: false,
      moreQueries: ['stromae', 'chanson française'], icon: Icons.public_rounded, colors: [Color(0xFF0052D4), Color(0xFFEF3B36)]);
  static const portuguese = Category(
      id: 'portuguese', title: 'Brazilian & Portuguese', subtitle: 'Funk • Sertanejo • Bossa', query: 'brazil', songQuery: 'portuguese songs', language: 'portuguese', strictLanguage: true, playlists: false,
      moreQueries: ['bossa nova', 'funk brasileiro'], icon: Icons.public_rounded, colors: [Color(0xFF009C3B), Color(0xFFFFDF00)]);
  static const turkish = Category(
      id: 'turkish', title: 'Turkish', subtitle: 'Türkçe', query: 'turkish', songQuery: 'turkish songs', language: 'turkish', strictLanguage: true, playlists: false,
      icon: Icons.public_rounded, colors: [Color(0xFFE30A17), Color(0xFF8E0E00)]);
  static const german = Category(
      id: 'german', title: 'German', subtitle: 'Deutsch', query: 'german', songQuery: 'german songs', language: 'german', strictLanguage: true, playlists: false,
      icon: Icons.public_rounded, colors: [Color(0xFF232526), Color(0xFFDD1818)]);
  static const italian = Category(
      id: 'italian', title: 'Italian', subtitle: 'Italiano', query: 'italian', songQuery: 'italian songs', language: 'italian', strictLanguage: true, playlists: false,
      icon: Icons.public_rounded, colors: [Color(0xFF009246), Color(0xFFCE2B37)]);
  static const indonesian = Category(
      id: 'indonesian', title: 'Indonesian', subtitle: 'Bahasa', query: 'indonesian', songQuery: 'indonesian songs', language: 'indonesian', strictLanguage: true, playlists: false,
      moreQueries: ['lagu indonesia'], icon: Icons.public_rounded, colors: [Color(0xFFCE1126), Color(0xFFF5F5F5)]);

  static const groups = <CatalogGroup>[
    CatalogGroup('mood', 'Moods', 'Music for how you feel',
        [chill, romantic, sad, party, workout, focus, sleep, happy, devotional, roadtrip, rain, lateNight, nostalgia, lofi]),
    CatalogGroup('era', 'Time machine', 'Journey through the decades',
        [trending, latest, era10, era00, era90, era80, era70, golden]),
    CatalogGroup('bengali', 'Bengali corner', 'বাংলা সঙ্গীত',
        [bengali, rabindra, nazrul, bengaliOld, bengaliAdhunik, bengaliBand, bengaliFilm, baul, durgaPuja, mahalaya]),
    CatalogGroup('india', 'Indian languages', 'Music from across India',
        [hindi, punjabi, tamil, telugu, malayalam, kannada, marathi, gujarati, bhojpuri, odia, assamese, haryanvi, urdu, rajasthani, garhwali, konkani, northeast, dogri, nepali, sinhala]),
    CatalogGroup('classical', 'Indian classical', 'Ragas, masters and timeless forms',
        [hindustani, hindustaniVocal, ragas, sitar, bansuri, santoor, shehnai, thumri, dhrupad, carnatic, carnaticVocal, veena, ghazal, sufi, instrumental, mantras, devotional]),
    CatalogGroup('folk', 'Folk & roots', 'From villages and festivals', [rajasthaniFolk, punjabiFolk, baul, bihu, garba, lavani, cokeStudio]),
    CatalogGroup('korean', 'Korean', '한국 음악 · K-Pop and beyond', [kpop, kgirls, kboys, kdrama, kballad, khiphop, krnb, trot]),
    CatalogGroup('genre', 'Genres', 'Pick your sound',
        [pop, rock, hiphop, edm, indie, acoustic, rnb, jazz, blues, metal, country, reggae, westernClassical, soundtracks, kids, lofi]),
    CatalogGroup('world', 'Around the world', 'Sounds from everywhere',
        [english, spanish, latin, french, portuguese, arabic, turkish, german, italian, jpop, indonesian, afro]),
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
    ArtistGroup('K-Pop', [
      'BTS', 'BLACKPINK', 'Jimin', 'Jung Kook', 'aespa', 'NewJeans', 'Stray Kids', 'LE SSERAFIM',
    ]),
    ArtistGroup('Classical maestros', [
      'Ravi Shankar', 'Bhimsen Joshi', 'Zakir Hussain', 'Hariprasad Chaurasia', 'Shivkumar Sharma', 'Bismillah Khan', 'Amjad Ali Khan', 'M. S. Subbulakshmi',
    ]),
    ArtistGroup('Around the world', [
      'Bad Bunny', 'Shakira', 'Stromae', 'Burna Boy', 'Wizkid', 'Amr Diab', 'YOASOBI', 'Tarkan',
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
  /// names paired with long ones).
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
    'rajasthani': 'Rajasthani',
  };

  /// Languages on the New releases page. The catalogue's release feed covers
  /// these directly...
  static const releaseFeedLanguages = <String, String>{
    ...languageChoices,
    'sanskrit': 'Sanskrit',
  };

  /// ...and these are found by searching for this year's songs in the language.
  static const releaseSearchLanguages = <String, String>{
    'korean': 'Korean',
    'spanish': 'Spanish',
    'japanese': 'Japanese',
    'french': 'French',
    'portuguese': 'Portuguese',
    'arabic': 'Arabic',
    'turkish': 'Turkish',
    'nepali': 'Nepali',
  };
}
