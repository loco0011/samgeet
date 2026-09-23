import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/deep_link.dart';
import '../data/saavn_api.dart';
import '../player/player_controller.dart';
import 'nav.dart';
import 'responsive.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart' show LibraryScreen, importPlaylistIds;
import 'screens/search_screen.dart';
import 'mood_theme.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/glass.dart';
import 'widgets/mini_player.dart';
import 'widgets/update_dialog.dart';

/// Bottom navigation (phones) or a side rail (tablets / landscape), with one
/// navigator per tab so the mini-player and navigation stay put while you dive
/// into albums, artists and playlists.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _keys = List.generate(4, (_) => GlobalKey<NavigatorState>());
  int _index = 0;
  StreamSubscription<String>? _toasts;
  final _deepLinks = DeepLinks();
  StreamSubscription<String>? _linkSub;

  static const _pages = <Widget>[
    HomeScreen(),
    ExploreScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  static const _destinations =
      <({IconData icon, IconData selected, String label})>[
        (
          icon: Icons.home_outlined,
          selected: Icons.home_rounded,
          label: 'Home',
        ),
        (
          icon: Icons.explore_outlined,
          selected: Icons.explore_rounded,
          label: 'Explore',
        ),
        (
          icon: Icons.search_rounded,
          selected: Icons.search_rounded,
          label: 'Search',
        ),
        (
          icon: Icons.library_music_outlined,
          selected: Icons.library_music_rounded,
          label: 'Library',
        ),
      ];

  @override
  void initState() {
    super.initState();
    _toasts = context.read<PlayerController>().messages.listen((m) {
      if (mounted) toast(context, m);
    });
    // Opened from a shared song/playlist link: at launch, or while the app was already running.
    _linkSub = _deepLinks.links.listen(_openLink);
    _deepLinks.initial().then((l) {
      if (l != null) _openLink(l);
    });
    // A newer release on GitHub? Ask once the home screen has settled.
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) checkForUpdate(context);
    });
  }

  Future<void> _openLink(String raw) async {
    final link = parseSharedLink(raw);
    if (link == null || !mounted) return;
    final api = context.read<SaavnApi>();
    final player = context.read<PlayerController>();
    switch (link) {
      case SharedSong():
        try {
          final found = await api.details([link.id]);
          if (found.isEmpty) throw ApiException('That song is not available');
          await player.playSingle(found.first, context: 'a shared song');
        } catch (e) {
          if (mounted) toast(context, 'Could not open that song: $e');
        }
      case SharedPlaylist():
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Add shared playlist?', style: TextStyle(fontWeight: FontWeight.w800)),
            content: Text('"${link.name}" has ${plural(link.ids.length, 'song')}. Add it to your library?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
            ],
          ),
        );
        if (ok == true && mounted) await importPlaylistIds(context, link.name, link.ids);
    }
  }

  @override
  void dispose() {
    _toasts?.cancel();
    _linkSub?.cancel();
    _deepLinks.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) {
      // Tapping the active tab returns to its root.
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  Widget _tabs() => Stack(
    children: [
      for (var i = 0; i < _pages.length; i++)
        Offstage(
          offstage: _index != i,
          child: TickerMode(
            enabled: _index == i,
            child: Navigator(
              key: _keys[i],
              onGenerateRoute: (_) => fadeRoute(Scaffold(body: _pages[i])),
            ),
          ),
        ),
    ],
  );

  /// Keeps content readable on very large screens.
  Widget _capped(Widget child) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Responsive.maxContent),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final wide = Responsive.isWide(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _keys[_index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: wide
            ? Row(
                children: [
                  _SideRail(
                    index: _index,
                    onSelect: _select,
                    destinations: _destinations,
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _capped(_tabs())),
                        _capped(const MiniPlayer()),
                      ],
                    ),
                  ),
                ],
              )
            : _tabs(),
        bottomNavigationBar: wide
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const MiniPlayer(),
                  _FloatingDock(index: _index, onSelect: _select, destinations: _destinations),
                ],
              ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, IconData selected, String label})> destinations;
  const _SideRail({
    required this.index,
    required this.onSelect,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final extended = size.width >= 1100;
    // A landscape phone is only ~360dp tall: drop the logo so four tabs always fit.
    final compact = size.height < 520;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.55),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          extended: extended,
          minExtendedWidth: 190,
          selectedIndex: index,
          onDestinationSelected: onSelect,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          indicatorColor: moodPalette(context).accent.withValues(alpha: 0.35),
          leading: compact
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 20),
                  child: extended
                      ? const GradientText(
                          'Samgeet',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                        )
                      : Image.asset('assets/mark-chrome.webp', height: 46),
                ),
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: Text(d.label),
              ),
          ],
        ),
      ),
    );
  }
}

/// A floating glass capsule. The selected tab expands into a glowing gradient pill.
class _FloatingDock extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  final List<({IconData icon, IconData selected, String label})> destinations;
  const _FloatingDock({required this.index, required this.onSelect, required this.destinations});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: GlassBox(
          radius: 34,
          blur: true,
          tint: AppColors.bg,
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Pressable(
                  onTap: () => onSelect(i),
                  scale: 0.9,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    height: 50,
                    padding: EdgeInsets.symmetric(horizontal: i == index ? 20 : 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: i == index ? mood.gradient : null,
                      boxShadow: i == index ? [BoxShadow(color: mood.accent.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 4))] : null,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(i == index ? destinations[i].selected : destinations[i].icon, size: 24, color: i == index ? Colors.white : AppColors.muted),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        child: i == index
                            ? Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(destinations[i].label, style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 13)),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
