import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/library_store.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/glass.dart';
import '../widgets/track_widgets.dart';

/// "Released today / this week": the catalogue's newest albums and singles,
/// straight from its release feed, in any language.
class NewReleasesScreen extends StatefulWidget {
  const NewReleasesScreen({super.key});

  @override
  State<NewReleasesScreen> createState() => _NewReleasesScreenState();
}

class _NewReleasesScreenState extends State<NewReleasesScreen> {
  static const _mine = '';
  static const _maxPages = 6;

  String _lang = _mine; // '' = the listener's own languages
  final List<MediaCard> _cards = [];
  List<Track> _songs = const [];
  int _page = 0;
  bool _loading = false, _done = false;
  Object? _error;
  int _request = 0; // a language switch mid-load drops the old answer

  bool get _bySearch => Catalog.releaseSearchLanguages.containsKey(_lang);

  List<String> get _languages => _lang == _mine ? context.read<LibraryStore>().languages : [_lang];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool force = false}) async {
    final req = ++_request;
    setState(() {
      _cards.clear();
      _songs = const [];
      _page = 0;
      _done = false;
      _error = null;
    });
    if (_bySearch) {
      setState(() => _loading = true);
      try {
        final songs = await context.read<SaavnApi>().latestSongs(_lang);
        if (req == _request) setState(() => _songs = songs);
      } catch (e) {
        if (req == _request) setState(() => _error = e);
      } finally {
        if (req == _request) setState(() => _loading = false);
      }
      return;
    }
    await _more(force: force);
  }

  Future<void> _more({bool force = false}) async {
    if (_loading || _done || _bySearch) return;
    final req = _request;
    setState(() => _loading = true);
    try {
      final page = await context.read<SaavnApi>().newReleases(_languages, page: _page + 1, force: force);
      if (req != _request) return;
      final known = {for (final c in _cards) '${c.kind}:${c.id}'};
      final fresh = page.where((c) => known.add('${c.kind}:${c.id}')).toList();
      final sorted = SaavnApi.sortByRelease([..._cards, ...fresh]);
      setState(() {
        _page++;
        _cards
          ..clear()
          ..addAll(sorted);
        _done = fresh.isEmpty || _page >= _maxPages;
      });
    } catch (e) {
      if (req == _request) setState(() => _error = e);
    } finally {
      if (req == _request) setState(() => _loading = false);
    }
  }

  void _pick(String lang) {
    if (lang == _lang) return;
    _lang = lang;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final choices = <String, String>{
      _mine: 'My languages',
      ...Catalog.releaseFeedLanguages,
      ...Catalog.releaseSearchLanguages,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('New releases'),
        actions: [IconButton(tooltip: 'Refresh', onPressed: () => _reload(force: true), icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
            children: [
              for (final e in choices.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GlassChip(label: e.value, dense: true, selected: _lang == e.key, onTap: () => _pick(e.key)),
                ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: mood.accent,
            backgroundColor: AppColors.surface2,
            onRefresh: () => _reload(force: true),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) _more();
                return false;
              },
              child: _body(),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    final empty = _bySearch ? _songs.isEmpty : _cards.isEmpty;
    if (empty && _loading) return const SingleChildScrollView(child: TrackListSkeleton());
    if (empty && _error != null) {
      return ListView(children: [
        const SizedBox(height: 60),
        EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Can\'t load new releases',
          message: 'Check your connection and try again.',
          action: GradientButton(label: 'Try again', compact: true, onTap: () => _reload(force: true)),
        ),
      ]);
    }
    if (empty) {
      return ListView(children: const [
        SizedBox(height: 60),
        EmptyState(icon: Icons.new_releases_outlined, title: 'Nothing new yet', message: 'Pull down to check again.'),
      ]);
    }
    if (_bySearch) {
      final player = context.read<PlayerController>();
      final ctx = 'new ${Catalog.releaseSearchLanguages[_lang]} songs';
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 30),
        itemCount: _songs.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PlayBar(
                onPlay: () => player.playTracks(_songs, context: ctx),
                onShuffle: () => player.playTracks(_songs, context: ctx, shuffleOn: true),
              ),
            );
          }
          return TrackTile(track: _songs[i - 1], showLike: true, onTap: () => player.playTracks(_songs, start: i - 1, context: ctx));
        },
      );
    }

    // Group under "Today", "Yesterday", "This week"...
    final rows = <Widget>[];
    String? heading;
    final now = DateTime.now();
    for (final c in _cards) {
      final h = releaseHeading(c.released, now);
      if (h != heading) {
        heading = h;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Text(h.toUpperCase(), style: const TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w800)),
        ));
      }
      rows.add(_ReleaseTile(card: c));
    }
    if (_loading) {
      rows.add(const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 30), children: rows);
  }
}

/// Which heading a release sits under.
String releaseHeading(DateTime? released, DateTime now) {
  if (released == null) return 'Recently';
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(released.year, released.month, released.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return 'This week';
  if (days < 14) return 'Last week';
  return 'Earlier this month';
}

class _ReleaseTile extends StatelessWidget {
  final MediaCard card;
  const _ReleaseTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final lang = card.language.isEmpty ? '' : '${card.language[0].toUpperCase()}${card.language.substring(1)}';
    final kind = card.kind == CardKind.album ? 'Album' : 'Single';
    return InkWell(
      onTap: () => openCard(context, card),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
        child: Row(children: [
          Artwork(card.art(150), size: 58, radius: 12, cacheSize: 150),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(card.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 3),
              Text(
                [kind, if (lang.isNotEmpty) lang, if (card.subtitle.isNotEmpty) card.subtitle].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ]),
          ),
          Icon(card.kind == CardKind.album ? Icons.chevron_right_rounded : Icons.play_circle_outline_rounded, color: AppColors.muted),
        ]),
      ),
    );
  }
}
