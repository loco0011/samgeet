import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/library_store.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shelves.dart';
import '../widgets/track_widgets.dart';

class _Results {
  final List<Track> songs;
  final List<MediaCard> albums;
  final List<MediaCard> playlists;
  final List<ArtistRef> artists;
  const _Results(this.songs, this.albums, this.playlists, this.artists);
  bool get isEmpty => songs.isEmpty && albums.isEmpty && playlists.isEmpty && artists.isEmpty;
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _typed = '';
  String? _submitted;
  List<String> _suggestions = const [];
  int _suggestSeq = 0;
  Future<_Results>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _typed = v);
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final seq = ++_suggestSeq;
      try {
        final s = await context.read<SaavnApi>().suggestions(v);
        if (mounted && seq == _suggestSeq) setState(() => _suggestions = s);
      } catch (_) {}
    });
  }

  void _submit(String q) {
    final query = q.trim();
    if (query.isEmpty) return;
    _focus.unfocus();
    context.read<LibraryStore>().addSearch(query);
    final api = context.read<SaavnApi>();
    setState(() {
      _controller.text = query;
      _typed = query;
      _submitted = query;
      _suggestions = const [];
      _results = () async {
        final r = await Future.wait([
          api.searchSongs(query, n: 30),
          api.searchAlbums(query, n: 12).catchError((_) => <MediaCard>[]),
          api.searchPlaylists(query, n: 12).catchError((_) => <MediaCard>[]),
          api.searchArtists(query, n: 12).catchError((_) => <ArtistRef>[]),
        ]);
        return _Results(
          (r[0] as List<Track>).where((t) => t.isPlayable).toList(),
          r[1] as List<MediaCard>,
          r[2] as List<MediaCard>,
          r[3] as List<ArtistRef>,
        );
      }();
    });
  }

  void _clear() {
    _controller.clear();
    setState(() {
      _typed = '';
      _submitted = null;
      _results = null;
      _suggestions = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Songs, artists, albums, moods…',
              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted),
              suffixIcon: _typed.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clear),
            ),
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            layoutBuilder: currentOnlyLayout,
            child: _body(context),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_submitted != null && _results != null && _suggestions.isEmpty) {
      return KeyedSubtree(key: ValueKey(_submitted), child: _ResultsView(future: _results!, query: _submitted!));
    }
    if (_typed.trim().length >= 2 && _suggestions.isNotEmpty) {
      return ListView(
        key: const ValueKey('suggest'),
        children: [
          for (final s in _suggestions)
            ListTile(
              leading: const Icon(Icons.north_west_rounded, size: 18, color: AppColors.muted),
              title: Text(s),
              onTap: () => _submit(s),
            ),
        ],
      );
    }
    return _Landing(key: const ValueKey('landing'), onPick: _submit);
  }
}

class _Landing extends StatelessWidget {
  final void Function(String) onPick;
  const _Landing({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
      if (lib.recentSearches.isNotEmpty) ...[
        SectionHeader('Recent searches', trailing: TextButton(onPressed: lib.clearSearches, child: const Text('Clear'))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in lib.recentSearches) ActionChip(avatar: const Icon(Icons.history_rounded, size: 16), label: Text(s), onPressed: () => onPick(s)),
          ]),
        ),
      ],
      const SectionHeader('Browse all', subtitle: 'Tap a mood, language or era'),
      CategoryGrid(
        items: [Catalog.bengali, Catalog.hindi, Catalog.romantic, Catalog.chill, Catalog.era90, Catalog.era80, Catalog.rabindra, Catalog.ghazal, Catalog.punjabi, Catalog.party, Catalog.workout, Catalog.lofi, Catalog.english, Catalog.kpop],
        onTap: (c) => openCategory(context, c),
      ),
    ]);
  }
}

class _ResultsView extends StatelessWidget {
  final Future<_Results> future;
  final String query;
  const _ResultsView({required this.future, required this.query});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Results>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(icon: Icons.wifi_off_rounded, title: 'Search failed', message: '${snap.error}');
        }
        if (!snap.hasData) return const SingleChildScrollView(child: TrackListSkeleton(count: 9));
        final r = snap.data!;
        if (r.isEmpty) return EmptyState(icon: Icons.search_off_rounded, title: 'No results for "$query"', message: 'Try a different spelling or another keyword.');

        return DefaultTabController(
          length: 4,
          child: Column(children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              indicator: const UnderlineTabIndicator(borderSide: BorderSide(width: 3, color: AppColors.pink), borderRadius: BorderRadius.all(Radius.circular(3))),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              unselectedLabelColor: AppColors.muted,
              tabs: [
                Tab(text: 'Songs (${r.songs.length})'),
                Tab(text: 'Artists (${r.artists.length})'),
                Tab(text: 'Albums (${r.albums.length})'),
                Tab(text: 'Playlists (${r.playlists.length})'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                r.songs.isEmpty
                    ? const EmptyState(icon: Icons.music_off_rounded, title: 'No songs found')
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 30),
                        itemCount: r.songs.length,
                        itemBuilder: (_, i) => TrackTile(
                          track: r.songs[i],
                          showLike: true,
                          onTap: () => context.read<PlayerController>().playSingle(r.songs[i]),
                        ),
                      ),
                _grid(context, r.artists.map((a) => MediaCard(kind: CardKind.artist, id: a.id, title: a.name, image: a.image)).toList(), circle: true),
                _grid(context, r.albums),
                _grid(context, r.playlists),
              ]),
            ),
          ]),
        );
      },
    );
  }

  Widget _grid(BuildContext context, List<MediaCard> cards, {bool circle = false}) {
    if (cards.isEmpty) return const EmptyState(icon: Icons.search_off_rounded, title: 'Nothing here');
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.70),
      itemCount: cards.length,
      itemBuilder: (_, i) => LayoutBuilder(
        builder: (_, box) => MediaCardTile(
          image: cards[i].art(500),
          title: cards[i].title,
          subtitle: cards[i].subtitle,
          size: box.maxWidth,
          circle: circle,
          onTap: () => openCard(context, cards[i]),
        ),
      ),
    );
  }
}
