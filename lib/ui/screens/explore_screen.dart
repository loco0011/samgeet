import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/catalog.dart';
import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shelves.dart';

/// Browse everything: moods, decades, Bengali corner, favourite singers, languages, genres, the world.
class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final byId = {for (final g in Catalog.groups) g.id: g};
    Widget group(String id) {
      final g = byId[id]!;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(g.title, subtitle: g.subtitle),
        CategoryGrid(items: g.items, onTap: (c) => openCategory(context, c)),
      ]);
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Text('Explore', style: TextStyle(fontFamily: kDisplay, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1)),
          ),
          group('mood'),
          group('era'),
          group('bengali'),
          const SectionHeader('Favourite singers', subtitle: 'Legends and today\'s voices'),
          for (final g in Catalog.artistGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(g.title, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.4)),
            ),
            _NamedArtistShelf(names: g.names),
            const SizedBox(height: 10),
          ],
          group('india'),
          group('classical'),
          group('genre'),
          group('world'),
        ],
      ),
    );
  }
}

/// Artists listed by name; each is resolved (photo + id) only when scrolled into view.
class _NamedArtistShelf extends StatelessWidget {
  final List<String> names;
  const _NamedArtistShelf({required this.names});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: names.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _ArtistByName(name: names[i]),
      ),
    );
  }
}

class _ArtistByName extends StatefulWidget {
  final String name;
  const _ArtistByName({required this.name});

  @override
  State<_ArtistByName> createState() => _ArtistByNameState();
}

class _ArtistByNameState extends State<_ArtistByName> {
  late final Future<ArtistRef?> _future = () async {
    try {
      final r = await context.read<SaavnApi>().searchArtists(widget.name, n: 3);
      return r.isEmpty ? null : r.first;
    } catch (_) {
      return null;
    }
  }();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ArtistRef?>(
      future: _future,
      builder: (context, snap) {
        final a = snap.data;
        return MediaCardTile(
          image: a?.image.replaceAll('50x50', '250x250').replaceAll('150x150', '250x250') ?? '',
          title: widget.name,
          size: 100,
          circle: true,
          onTap: () => openArtist(context, a ?? ArtistRef(id: '', name: widget.name)),
        );
      },
    );
  }
}
