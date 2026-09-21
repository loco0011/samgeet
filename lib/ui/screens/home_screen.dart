import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../app_info.dart';
import '../../data/catalog.dart';
import '../../data/library_store.dart';
import '../../data/profile.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../engine/recommendation_service.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import '../widgets/profile_avatar.dart';
import '../mood_theme.dart';
import '../widgets/shelves.dart';
import '../widgets/track_widgets.dart';
import 'settings_screen.dart';
import 'sign_in_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData> _home;
  late Future<List<Track>> _mix;
  String _langKey = '';
  int? _profileKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final lib = context.read<LibraryStore>();
    _langKey = lib.languages.join(',');
    _profileKey = lib.profile?.createdAt;
    _home = context.read<SaavnApi>().home(lib.languages);
    _mix = context.read<RecommendationService>().madeForYou().catchError((_) => <Track>[]);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _home.catchError((_) => const HomeData());
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    // Language change → reload the charts.
    if (lib.languages.join(',') != _langKey || lib.profile?.createdAt != _profileKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_load);
      });
    }
    final hour = DateTime.now().hour;
    final quick = <Track>[
      ...{for (final t in [...lib.history, ...lib.favorites]) t.id: t}.values,
    ].take(6).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.pink,
        backgroundColor: AppColors.surface2,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _Header(greeting: Catalog.greeting(hour), profile: lib.profile)),
            SliverToBoxAdapter(child: _LanguageChips(selected: lib.languages, onChanged: lib.setLanguages)),

            if (quick.isNotEmpty) SliverToBoxAdapter(child: _QuickPicks(tracks: quick)),

            // Made for you
            SliverToBoxAdapter(
              child: FutureBuilder<List<Track>>(
                future: _mix,
                builder: (context, snap) {
                  final mix = snap.data ?? const <Track>[];
                  if (mix.isEmpty) return const SizedBox.shrink();
                  return _MadeForYou(mix: mix, taste: lib);
                },
              ),
            ),

            SliverToBoxAdapter(child: SectionHeader('For your ${_partOfDay(hour)}', subtitle: 'Picked for this time of day')),
            SliverToBoxAdapter(child: CategoryStrip(items: _forYou(lib, hour), onTap: (c) => openCategory(context, c))),

            SliverToBoxAdapter(
              child: FutureBuilder<HomeData>(
                future: _home,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'No connection',
                        message: 'Connect to the internet to see what\'s trending.',
                        action: GradientButton(label: 'Retry', icon: Icons.refresh_rounded, compact: true, onTap: () => setState(_load)),
                      ),
                    );
                  }
                  if (!snap.hasData) return const _HomeSkeleton();
                  final d = snap.data!;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (d.trending.isNotEmpty) ...[
                      const SectionHeader('Trending now', subtitle: 'What everyone is playing'),
                      HeroCarousel(cards: d.trending, onTap: (c) => openCard(context, c)),
                    ],
                    if (d.newAlbums.isNotEmpty) ...[
                      const SectionHeader('New releases'),
                      PosterGrid(cards: d.newAlbums.take(6).toList(), onTap: (c) => openCard(context, c)),
                    ],
                    if (d.charts.isNotEmpty) ...[
                      const SectionHeader('Charts', subtitle: 'Top of the pops, updated daily'),
                      CardShelf(cards: d.charts, onTap: (c) => openCard(context, c)),
                    ],
                    const SectionHeader('Time machine', subtitle: 'Journey through the decades'),
                    CategoryStrip(items: const [Catalog.era10, Catalog.era00, Catalog.era90, Catalog.era80, Catalog.era70, Catalog.golden], onTap: (c) => openCategory(context, c)),
                    if (d.playlists.isNotEmpty) ...[
                      const SectionHeader('Top playlists'),
                      CardShelf(cards: d.playlists, onTap: (c) => openCard(context, c)),
                    ],
                    const SectionHeader('Bengali corner', subtitle: 'বাংলা সঙ্গীত'),
                    CategoryStrip(items: const [Catalog.bengali, Catalog.rabindra, Catalog.nazrul, Catalog.bengaliOld, Catalog.bengaliAdhunik, Catalog.bengaliBand], onTap: (c) => openCategory(context, c)),
                    if (d.artists.isNotEmpty) ...[
                      const SectionHeader('Artists to explore'),
                      CardShelf(cards: d.artists.where((c) => c.kind == CardKind.artist).toList(), size: 92, onTap: (c) => openCard(context, c)),
                    ],
                    const SectionHeader('Moods', subtitle: 'Music for how you feel'),
                    CategoryStrip(items: Catalog.groups.first.items, onTap: (c) => openCategory(context, c)),
                  ]);
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }

  /// The moods the listener picked come first, then the ones that suit the hour.
  List<Category> _forYou(LibraryStore lib, int hour) {
    final picked = [for (final id in lib.profile?.moods ?? const <String>[]) ?Catalog.byId[id]];
    return <Category>{...picked, ...Catalog.forHour(hour)}.take(6).toList();
  }

  String _partOfDay(int h) => h >= 5 && h < 12 ? 'morning' : h >= 12 && h < 17 ? 'afternoon' : h >= 17 && h < 22 ? 'evening' : 'night';
}

/// Guests see the app logo and name. Once signed in, the logo becomes the
/// listener's avatar and the name becomes theirs (edited from their profile).
class _Header extends StatelessWidget {
  final String greeting;
  final Profile? profile;
  const _Header({required this.greeting, required this.profile});

  @override
  Widget build(BuildContext context) {
    final palette = moodPalette(context);
    final p = profile;
    final name = p?.name.trim() ?? '';
    final signedIn = p != null && name.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 6),
      child: Row(children: [
        if (signedIn)
          Pressable(
            onTap: () => pushPage(context, const SignInScreen()),
            child: ProfileAvatar(initials: p.initials, avatar: p.avatar),
          )
        else
          Image.asset('assets/mark-chrome.webp', height: 54),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: palette.light, boxShadow: [BoxShadow(color: palette.light, blurRadius: 8)])),
              const SizedBox(width: 8),
              Text(greeting.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2)),
            ]),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: GradientText(signedIn ? name : kAppName, gradient: palette.textGradient, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1)),
            ),
          ]),
        ),
        Pressable(
          onTap: () => pushPage(context, const SettingsScreen()),
          child: const GlassBox(radius: 22, width: 44, height: 44, child: Center(child: Icon(Icons.tune_rounded, size: 21))),
        ),
      ]).animate().fadeIn(duration: 500.ms).slideY(begin: -0.15, end: 0, curve: Curves.easeOutCubic),
    );
  }
}

class _LanguageChips extends StatelessWidget {
  final List<String> selected;
  final void Function(List<String>) onChanged;
  const _LanguageChips({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        children: [
          for (final e in Catalog.languageChoices.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GlassChip(
                label: e.value,
                selected: selected.contains(e.key),
                onTap: () {
                  final next = [...selected];
                  selected.contains(e.key) ? next.remove(e.key) : next.add(e.key);
                  onChanged(next);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickPicks extends StatelessWidget {
  final List<Track> tracks;
  const _QuickPicks({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width >= 900 ? 3 : 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 10, crossAxisSpacing: 10, mainAxisExtent: 58),
        itemCount: tracks.length,
        itemBuilder: (_, i) {
          final t = tracks[i];
          return Pressable(
            onTap: () => context.read<PlayerController>().playTracks(tracks, start: i),
            onLongPress: () => showTrackMenu(context, t),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(children: [
                Artwork(t.image, size: 58, radius: 0, cacheSize: 150),
                const SizedBox(width: 10),
                Expanded(child: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.25))),
                const SizedBox(width: 8),
              ]),
            ),
          ).animate().fadeIn(delay: (50 * i).ms, duration: 350.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}

/// A hero card for the personalised mix.
class _MadeForYou extends StatelessWidget {
  final List<Track> mix;
  final LibraryStore taste;
  const _MadeForYou({required this.mix, required this.taste});

  @override
  Widget build(BuildContext context) {
    final top = taste.taste.topArtists(n: 3).map((a) => a.name).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('Made for you', subtitle: 'Tuned to what you\'ve been loving'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Pressable(
          onTap: () => context.read<PlayerController>().playTracks(mix, context: null),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: moodPalette(context).gradient,
              boxShadow: [BoxShadow(color: moodPalette(context).accent.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))],
            ),
            child: Row(children: [
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(children: [
                  for (var i = 2; i >= 0; i--)
                    Positioned(
                      left: i * 14.0,
                      top: i * 3.0,
                      child: Transform.rotate(angle: (i - 1) * 0.08, child: Artwork(mix[i].image, size: 70, radius: 14, cacheSize: 200)),
                    ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your Daily Mix', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(
                    top.isEmpty ? '${mix.length} songs picked for you' : 'With ${top.join(', ')} & more',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                  ),
                ]),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 32),
              ),
            ]),
          ),
        ),
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic),
      const SizedBox(height: 14),
      TrackShelf(
        tracks: mix,
        onTap: (t, i) => context.read<PlayerController>().playTracks(mix, start: i),
        onLongPress: (t) => showTrackMenu(context, t),
      ),
    ]);
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget row() => SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SkeletonBox(width: 150, height: 150, radius: 18),
              SizedBox(height: 10),
              SkeletonBox(width: 110, height: 13, radius: 6),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 26, 20, 12), child: SkeletonBox(width: 150, height: 20, radius: 8)),
      row(),
      const Padding(padding: EdgeInsets.fromLTRB(20, 26, 20, 12), child: SkeletonBox(width: 120, height: 20, radius: 8)),
      row(),
    ]);
  }
}
