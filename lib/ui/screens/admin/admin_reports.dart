import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/admin_service.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/glass.dart';
import 'admin_widgets.dart';

// The admin's report screens: Overview, Listeners (and one listener), Places (and one city) and
// App updates. They show what the web panel shows, from the same server reports.

// ================================================================ overview

class OverviewTab extends StatefulWidget {
  final void Function(int tab) goTo;
  const OverviewTab({super.key, required this.goTo});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> with AutomaticKeepAliveClientMixin {
  String _range = '7';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final admin = context.read<AdminService>();
    return ReportView(
      reloadKey: _range,
      load: () async {
        final o = await admin.overview(_range);
        final l = await admin.listening(_range);
        return o == null ? null : J({...o.raw, 'listening': l?.raw ?? const {}});
      },
      header: [
        RangeChips(value: _range, onChanged: (r) => setState(() => _range = r)),
        const SizedBox(height: 12),
      ],
      build: (o) {
        final k = o.o('kpi');
        final a = o.o('active');
        final h = o.o('habits');
        final l = o.o('listening');
        final daily = o.list('daily');
        final (listeners, prevL) = k.pair('listeners');
        final (plays, prevP) = k.pair('plays');
        final (hours, prevH) = k.pair('hours');
        final (newUsers, prevN) = k.pair('new_users');
        final ad = o.o('adoption');
        final latest = ad.o('latest');
        return [
          StatGrid(
            children: [
              StatTile(
                label: 'Listeners',
                value: fmt(listeners),
                change: ChangeChip(listeners, prevL),
                sub: '${fmt(k.i('members'))} signed in · ${fmt(k.i('guests'))} guests',
              ),
              StatTile(label: 'Plays', value: fmt(plays), change: ChangeChip(plays, prevP), sub: '${fmt(k.i('songs'))} different songs'),
              StatTile(
                label: 'Hours listened',
                value: hours.toStringAsFixed(1),
                change: ChangeChip(hours, prevH),
                sub: listeners > 0 ? '${(hours * 60 / listeners).round()} min per listener' : null,
              ),
              StatTile(
                label: 'New accounts',
                value: fmt(newUsers),
                change: ChangeChip(newUsers, prevN),
                sub: '${fmt(k.i('converted'))} were guests first',
                onTap: () => widget.goTo(1),
              ),
            ],
          ),
          GlassBox(
            radius: 18,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                _Mini(fmt(a.i('online_now')), 'online now', dot: true),
                _Mini(fmt(a.i('today')), 'active today'),
                _Mini(fmt(a.i('week')), 'this week'),
                _Mini(fmt(a.i('accounts')), 'accounts'),
              ],
            ),
          ),
          AdminPanel(
            title: 'Daily listeners',
            note: 'signed in + guests',
            child: Column(
              children: [
                MiniBars(values: daily.map((d) => d.i('members')).toList(), second: daily.map((d) => d.i('guests')).toList(), labels: dayLabels(daily)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Legend(Theme.of(context).colorScheme.primary, 'Signed in'),
                    const SizedBox(width: 16),
                    const _Legend(Color(0xFF5B6B9A), 'Guests'),
                  ],
                ),
              ],
            ),
          ),
          AdminPanel(title: 'Top songs', note: kRanges[_range]!.toLowerCase(), child: SongList(o.list('top_songs').take(8).toList())),
          AdminPanel(
            title: 'Most active listeners',
            trailing: PanelLink('All', () => widget.goTo(1)),
            child: Column(
              children: [
                for (final p in o.list('top_listeners'))
                  PersonRow(
                    p: p,
                    sub: p.s('place').isNotEmpty ? p.s('place') : p.s('email'),
                    trailing: Text(mins(p.i('minutes')), style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => pushPage(context, ListenerPage(id: p.i('id'), name: p.s('name'))),
                  ),
                if (o.list('top_listeners').isEmpty) const Text('Nobody yet.', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          AdminPanel(title: 'Top singers', child: BarList(barRows(o.list('top_artists').take(6).toList()))),
          AdminPanel(
            title: 'Top cities',
            trailing: PanelLink('Places', () => widget.goTo(2)),
            child: BarList(
              [for (final c in o.list('top_cities')) (c.s('city'), c.i('accounts'))],
              onTap: (i) {
                final c = o.list('top_cities')[i];
                pushPage(context, PlacePage(city: c.s('city'), country: c.s('country')));
              },
              empty: 'Nobody has shared a place yet.',
            ),
          ),
          AdminPanel(
            title: 'App versions',
            trailing: PanelLink('Updates', () => widget.goTo(4)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (latest.s('version').isNotEmpty) ...[
                  Text(
                    '${ad.i('on_latest_pct')}% on ${latest.s('version')} · ${fmt(ad.i('behind'))} phones behind',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: ad.i('on_latest_pct') / 100, minHeight: 7, backgroundColor: Colors.white10),
                  ),
                  const SizedBox(height: 12),
                ],
                BarList([for (final v in ad.list('versions').take(5)) ('${v.s('version')}${v.b('latest') ? ' (latest)' : ''}', v.i('phones'))]),
              ],
            ),
          ),
          AdminPanel(
            title: 'When people listen',
            note: 'plays by hour',
            child: MiniBars(values: l.nums('hours'), labels: hourLabels, height: 110, color: const Color(0xFFE0823F)),
          ),
          AdminPanel(
            title: 'Listening habits',
            child: Column(
              children: [
                FactRow('Heard to the end', h['completed_pct'] == null ? '—' : '${h.i('completed_pct')}%'),
                FactRow('Skipped', h['skipped_pct'] == null ? '—' : '${h.i('skipped_pct')}%'),
                FactRow('Played offline', fmt(h.i('offline'))),
                FactRow('Likes · downloads', '${fmt(h.i('likes'))} · ${fmt(h.i('downloads'))}'),
                FactRow('Searches', fmt(h.i('searches'))),
                FactRow('Shares · playlists', '${fmt(h.i('shares'))} · ${fmt(h.i('playlists'))}'),
              ],
            ),
          ),
          AdminPanel(title: 'Top searches', child: BarList(barRows(l.list('searches').take(8).toList()))),
          AdminPanel(title: 'Languages played', child: BarList(barRows(l.list('languages')))),
          AdminPanel(title: 'Where plays start', child: BarList(barRows(l.list('sources')))),
        ];
      },
    );
  }
}

class _Mini extends StatelessWidget {
  final String value, label;
  final bool dot;
  const _Mini(this.value, this.label, {this.dot = false});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              value,
              style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
    ],
  );
}

// ================================================================ listeners

const _filters = {'all': 'All', 'today': 'Active today', 'week': 'This week', 'inactive': 'Away 30+ days', 'blocked': 'Blocked'};
const _sorts = {'recent': 'Last seen', 'listening': 'Most listening', 'joined': 'Newest', 'name': 'Name'};

class ListenersTab extends StatefulWidget {
  const ListenersTab({super.key});

  @override
  State<ListenersTab> createState() => _ListenersTabState();
}

class _ListenersTabState extends State<ListenersTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _filter = 'all', _sort = 'recent', _q = '';
  final List<J> _items = [];
  J _counts = J.empty;
  int _page = 0, _total = 0;
  bool _loading = false, _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _items.clear();
    _page = 0;
    _total = 0;
    await _more();
  }

  Future<void> _more() async {
    if (_loading || (_page > 0 && _items.length >= _total)) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final r = await context.read<AdminService>().users(filter: _filter, q: _q, sort: _sort, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r == null) {
        _failed = true;
        return;
      }
      _page++;
      _total = r.i('total');
      _counts = r.o('counts');
      _items.addAll(r.list('users'));
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) _more();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                          _reload();
                        },
                      ),
              ),
              onSubmitted: (v) {
                setState(() => _q = v.trim());
                _reload();
              },
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _filters.entries) ...[
                    GlassChip(
                      dense: true,
                      label: _counts['all'] == null ? e.value : '${e.value} ${fmt(_counts.i(e.key))}',
                      selected: _filter == e.key,
                      onTap: () {
                        setState(() => _filter = e.key);
                        _reload();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(_total == 0 ? '' : '${fmt(_total)} listeners', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const Spacer(),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (s) {
                    setState(() => _sort = s);
                    _reload();
                  },
                  itemBuilder: (_) => [for (final e in _sorts.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort_rounded, size: 18, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Text(
                          _sorts[_sort]!,
                          style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            GlassBox(
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (final u in _items)
                    PersonRow(
                      p: u,
                      sub: [
                        u.s('place').isNotEmpty ? u.s('place') : u.s('email'),
                        if (u.s('version').isNotEmpty) 'v${u.s('version')}${u.b('outdated') ? ' (old)' : ''}',
                      ].join(' · '),
                      trailing: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(mins(u.i('minutes')), style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          SeenDot(u.time('last_seen')),
                        ],
                      ),
                      onTap: () async {
                        await pushPage(context, ListenerPage(id: u.i('id'), name: u.s('name')));
                      },
                    ),
                  if (_items.isEmpty && !_loading)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _failed ? 'Couldn\'t load listeners. Pull down to try again.' : 'Nobody here.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  if (_loading) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Minutes cover the last 30 days.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything about one listener.
class ListenerPage extends StatefulWidget {
  final int id;
  final String name;
  const ListenerPage({super.key, required this.id, required this.name});

  @override
  State<ListenerPage> createState() => _ListenerPageState();
}

class _ListenerPageState extends State<ListenerPage> {
  final _view = GlobalKey<ReportViewState>();

  Future<void> _act(J u, String what) async {
    final admin = context.read<AdminService>();
    final blocked = u.s('status') == 'blocked';
    final (title, text, button) = switch (what) {
      'signout' => ('Sign out everywhere?', '${u.s('name')} is signed out on every phone. Their library stays on the server.', 'Sign out'),
      _ =>
        blocked
            ? ('Unblock ${u.s('name')}?', 'They can sign in again.', 'Unblock')
            : ('Block ${u.s('name')}?', 'They are signed out everywhere and can\'t sign in again until you unblock them.', 'Block'),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(button),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = what == 'signout' ? await admin.signOutUser(widget.id) : await admin.toggleBlock(widget.id);
    if (!mounted) return;
    toast(context, done ? 'Done' : 'Couldn\'t do that. Try again.');
    if (done) _view.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    J? last;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (last != null) _act(last!, v);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'signout', child: Text('Sign out everywhere')),
              PopupMenuItem(value: 'block', child: Text('Block or unblock')),
            ],
          ),
        ],
      ),
      body: ReportView(
        key: _view,
        load: () => admin.user(widget.id),
        build: (u) {
          last = u;
          final t = u.o('totals');
          final place = u.s('place_label');
          final daily = u.list('daily');
          final tastes = u.o('tastes');
          final seen = u.time('last_seen');
          final active = seen != null && DateTime.now().difference(seen).inHours < 24;
          return [
            GlassBox(
              radius: 22,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  PersonAvatar(u, size: 64),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              u.s('name'),
                              style: const TextStyle(fontFamily: kDisplay, fontSize: 19, fontWeight: FontWeight.w800),
                            ),
                            if (u.s('status') == 'blocked') const Tag('blocked', color: kRed) else if (active) const Tag('active today', color: kGreen),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(u.s('email'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Text('Joined ${day(u.time('joined'))} · seen ${ago(seen).toLowerCase()}', style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined, size: 14, color: AppColors.muted),
                            const SizedBox(width: 4),
                            Expanded(child: Text(place.isEmpty ? 'Place not shared' : place, style: const TextStyle(fontSize: 12.5))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            StatGrid(
              columns: 3,
              children: [
                StatTile(label: 'Plays', value: fmt(t.i('plays')), sub: t['skip_pct'] == null ? null : '${t.i('skip_pct')}% skipped'),
                StatTile(label: 'Hours', value: t.d('hours').toStringAsFixed(1), sub: '${fmt(t.i('days'))} days'),
                StatTile(label: 'Likes', value: fmt(t.i('likes')), sub: '${fmt(t.i('downloads'))} downloads'),
                StatTile(label: 'Searches', value: fmt(t.i('searches')), sub: '${fmt(t.i('shares'))} shares'),
                StatTile(label: 'Messages', value: fmt(u.o('messages').i('got')), sub: '${fmt(u.o('messages').i('opened'))} opened'),
                StatTile(label: 'Look', value: _cap(u.s('player_style')), sub: 'player'),
              ],
            ),
            AdminPanel(
              title: 'Listening, last 30 days',
              note: 'minutes a day',
              child: MiniBars(values: daily.map((d) => d.i('minutes')).toList(), labels: dayLabels(daily), height: 120),
            ),
            AdminPanel(
              title: 'Time of day',
              note: 'plays by hour',
              child: MiniBars(values: u.nums('hours'), labels: hourLabels, height: 90, color: const Color(0xFFE0823F)),
            ),
            AdminPanel(title: 'Their top songs', child: SongList(u.list('top_songs'))),
            AdminPanel(title: 'Their top singers', child: BarList(barRows(u.list('top_artists')))),
            AdminPanel(title: 'Languages played', child: BarList(barRows(u.list('languages')))),
            if (u.list('searches').isNotEmpty)
              AdminPanel(
                title: 'Recent searches',
                child: Wrap(spacing: 6, runSpacing: 6, children: [for (final s in u.list('searches')) _Chip(s.s('text'))]),
              ),
            if (tastes.raw.isNotEmpty)
              AdminPanel(
                title: 'Picked at sign-up',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final kv in const {'language': 'Languages', 'mood': 'Moods', 'artist': 'Singers'}.entries)
                      if (tastes[kv.key] is List) ...[
                        Text(kv.value, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [for (final v in tastes[kv.key] as List) _Chip('$v')]),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            AdminPanel(
              title: 'Phones',
              note: '${u.i('sessions')} signed in now',
              child: Column(
                children: [
                  for (final d in u.list('devices'))
                    FactRow(
                      '${d.s('name')}\nAndroid ${d.s('android')} · v${d.s('version')}${d.b('outdated') ? ' · update waiting' : ''}',
                      ago(d.time('last_seen')),
                    ),
                  if (u.list('devices').isEmpty) const Text('No phone on record.', style: TextStyle(color: AppColors.muted)),
                ],
              ),
            ),
            AdminPanel(
              title: 'Activity',
              note: 'latest first',
              child: Column(
                children: [
                  for (final e in u.list('timeline'))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 74,
                            child: Text(ago(e.time('at')), style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                          ),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: e.s('label'),
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  if (e.s('title').isNotEmpty) TextSpan(text: ' ${e.s('title')}'),
                                  if (e.s('artist').isNotEmpty)
                                    TextSpan(
                                      text: ' · ${e.s('artist')}',
                                      style: const TextStyle(color: AppColors.muted),
                                    ),
                                  if (e.s('title').isEmpty && e.s('detail').isNotEmpty)
                                    TextSpan(
                                      text: ' “${e.s('detail')}”',
                                      style: const TextStyle(color: AppColors.muted),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ];
        },
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? '—' : s[0].toUpperCase() + s.substring(1);

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.outline),
    ),
    child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
  );
}

// ================================================================ places

class PlacesTab extends StatelessWidget {
  const PlacesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    return ReportView(
      load: admin.places,
      build: (p) => [
        StatGrid(
          children: [
            StatTile(label: 'Cities', value: fmt(p.list('cities').length), sub: '${fmt(p.list('countries').length)} countries'),
            StatTile(label: 'Accounts with a place', value: fmt(p.i('located_accounts')), sub: '${p.i('coverage_pct')}% of ${fmt(p.i('accounts'))}'),
          ],
        ),
        AdminPanel(
          title: 'Cities',
          note: 'tap one to see who listens there',
          child: Column(
            children: [
              for (final c in p.list('cities'))
                InkWell(
                  onTap: () => pushPage(context, PlacePage(city: c.s('city'), country: c.s('country'))),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.s('city'), style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                [
                                  [c.s('region'), if (c.s('country') != 'India') c.s('country')].where((s) => s.isNotEmpty).join(', '),
                                  '${fmt(c.i('active'))} active this week',
                                  '${fmt(c.i('plays'))} plays',
                                ].where((s) => s.isNotEmpty).join(' · '),
                                maxLines: 2,
                                style: const TextStyle(color: AppColors.muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          fmt(c.i('accounts')),
                          style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const Text(' accounts', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              if (p.list('cities').isEmpty) const Text('Nobody has shared a place yet.', style: TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
        AdminPanel(title: 'Countries', child: BarList([for (final c in p.list('countries')) (c.s('country'), c.i('accounts'))])),
        AdminPanel(
          title: 'Phone region',
          note: 'every install',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BarList(barRows(p.list('phone_regions'))),
              const SizedBox(height: 8),
              const Text(
                'From each phone\'s language setting, so it covers guests too, but only says which country the phone is set up for.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const Text(
          'Places come from listeners who agreed to share device details when signing in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 11.5),
        ),
      ],
    );
  }
}

/// One city: who listens there and what they play.
class PlacePage extends StatelessWidget {
  final String city, country;
  const PlacePage({super.key, required this.city, required this.country});

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    return Scaffold(
      appBar: AppBar(title: Text(city)),
      body: ReportView(
        load: () => admin.place(city, country),
        build: (c) => [
          Text(
            '${[c.s('region'), c.s('country')].where((s) => s.isNotEmpty).join(', ')} · ${plural(c.list('people').length, 'account')}, ${plural(c.i('guest_phones'), 'guest phone')}',
            style: const TextStyle(color: AppColors.muted),
          ),
          AdminPanel(
            title: 'Who listens here',
            note: 'last 30 days',
            child: Column(
              children: [
                for (final u in c.list('people'))
                  PersonRow(
                    p: u,
                    sub: '${fmt(u.i('plays'))} plays · ${ago(u.time('last_seen')).toLowerCase()}',
                    trailing: Text(mins(u.i('minutes')), style: const TextStyle(fontWeight: FontWeight.w800)),
                    onTap: () => pushPage(context, ListenerPage(id: u.i('id'), name: u.s('name'))),
                  ),
                if (c.list('people').isEmpty) const Text('Only guests here.', style: TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          AdminPanel(title: 'Top songs here', child: SongList(c.list('top_songs'))),
          AdminPanel(title: 'Top singers here', child: BarList(barRows(c.list('top_artists')))),
        ],
      ),
    );
  }
}

// ================================================================ app updates

class UpdatesTab extends StatefulWidget {
  final VoidCallback onRemind;
  final String? webPanel;
  const UpdatesTab({super.key, required this.onRemind, this.webPanel});

  @override
  State<UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<UpdatesTab> {
  final _view = GlobalKey<ReportViewState>();

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    return ReportView(
      key: _view,
      load: admin.releases,
      build: (r) {
        final a = r.o('adoption');
        final l = a.o('latest');
        final rem = r.o('reminder');
        return [
          StatGrid(
            children: [
              StatTile(
                label: 'Latest version',
                value: l.s('version').isEmpty ? '—' : l.s('version'),
                sub: l.s('version').isEmpty ? 'nothing published' : 'build ${l.i('build')}${l.b('required') ? ' · required' : ''}',
              ),
              StatTile(
                label: 'On the latest',
                value: '${a.i('on_latest_pct')}%',
                sub: '${fmt(a.i('on_latest'))} of ${fmt(a.i('active_phones'))} active phones',
              ),
            ],
          ),
          if (rem.i('behind') > 0)
            GlassBox(
              radius: 20,
              tint: AppColors.pink.withValues(alpha: 0.12),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmt(rem.i('behind'))} phones aren\'t on ${rem.s('version')} yet',
                    style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Send a reminder that only goes to apps older than the latest version, with an “Update now” button.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.pink, foregroundColor: Colors.white),
                    onPressed: widget.onRemind,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Remind them', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          AdminPanel(
            title: 'Versions in use',
            note: 'active phones, 30 days',
            child: BarList([for (final v in a.list('versions')) ('${v.s('version')}${v.b('latest') ? ' (latest)' : ''}', v.i('phones'))]),
          ),
          AdminPanel(
            title: 'Published versions',
            child: Column(
              children: [
                for (final v in r.list('releases'))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(v.s('version'), style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text('build ${v.i('build')}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  v.b('published') ? const Tag('live', color: kGreen) : const Tag('draft'),
                                  if (v.b('required')) const Tag('required', color: kAmber),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text('${fmt(v.i('phones'))} phones on it · ${day(v.time('at'))}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              if (v.nums('headlines').isEmpty && v['headlines'] is List && (v['headlines'] as List).isNotEmpty)
                                Text((v['headlines'] as List).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final done = await admin.toggleRelease(v.i('id'));
                            if (!context.mounted) return;
                            toast(context, done ? (v.b('published') ? 'Unpublished' : 'Published') : 'Couldn\'t change it. Try again.');
                            if (done) _view.currentState?.reload();
                          },
                          child: Text(v.b('published') ? 'Unpublish' : 'Publish'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Text(
            'To publish a new version, upload it from the web panel (App updates).',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ];
      },
    );
  }
}
