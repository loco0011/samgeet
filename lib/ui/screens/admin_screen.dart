import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/admin_service.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/account_widgets.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';
import 'admin/admin_reports.dart';
import 'admin/admin_widgets.dart';

const _styles = {'info': 'Info', 'celebrate': 'Celebrate', 'warning': 'Warning'};
const _showAs = {'both': 'Popup + notification', 'popup': 'Popup only', 'system': 'Notification only'};
const _audience = {'all': 'Everyone', 'signed_in': 'Signed in', 'guests': 'Guests', 'outdated': 'Not on the latest version'};
const _actions = {'none': 'No button link', 'update': 'Update the app', 'url': 'Open a link', 'search': 'Search for…'};
const _tabs = {'all': 'All', 'web': 'From the web', 'app': 'From the app', 'update': 'Update reminders'};
const _followUps = {
  'outdated': ('Only phones still on an old version', 'Apps older than the newest version, whatever they did with this message.'),
  'missed': ('Only phones that never got it', 'New installs, and people who haven\'t opened the app since it went out.'),
  'unopened': ('Only phones that got it but didn\'t open it', 'They closed it or never answered.'),
  'all': ('Everyone it was meant for', 'A fresh copy for everyone, even people who already opened it.'),
};

String _iconFor(String style) => switch (style) {
  'celebrate' => '🎉',
  'warning' => '📣',
  _ => '🔔',
};

List<Color> _headerColors(String style) => switch (style) {
  'celebrate' => const [Color(0xFFB5531A), Color(0xFFD0284F), Color(0xFF7A1232)],
  'warning' => const [Color(0xFF8A5A12), Color(0xFFE0A33F), Color(0xFF7A1232)],
  _ => const [Color(0xFF7A1232), Color(0xFFD0284F), Color(0xFFE0823F)],
};

/// Samgeet's admin tools inside the app: the same reports as the web panel (overview, listeners,
/// places, app versions) and sending messages. Opens from Settings (tap the version line 7 times).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this)..addListener(() => setState(() {}));
  final _messages = GlobalKey<_MessagesTabState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _remind() async {
    _tabs.animateTo(3);
    final sent = await pushPage<bool>(context, const ComposePage(updateReminder: true));
    if (sent == true) _messages.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    if (!admin.signedIn) return _SignIn(onDone: () => setState(() {}));
    final web = admin.webPanel;
    // Sections are tabs under the title (not a bar at the bottom), so they never sit on top of the
    // app's own dock.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Samgeet admin'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'web' && web != null) {
                await launchUrl(Uri.parse(web), mode: LaunchMode.externalApplication);
              } else if (v == 'out') {
                await admin.signOut();
                if (mounted) setState(() {});
              }
            },
            itemBuilder: (_) => [
              if (web != null) const PopupMenuItem(value: 'web', child: Text('Open the web panel')),
              const PopupMenuItem(value: 'out', child: Text('Sign out of admin')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.pink,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          unselectedLabelColor: AppColors.muted,
          tabs: const [
            Tab(icon: Icon(Icons.insights_rounded, size: 20), text: 'Overview', iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.people_rounded, size: 20), text: 'Listeners', iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.place_rounded, size: 20), text: 'Places', iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.campaign_rounded, size: 20), text: 'Messages', iconMargin: EdgeInsets.only(bottom: 2)),
            Tab(icon: Icon(Icons.system_update_rounded, size: 20), text: 'Updates', iconMargin: EdgeInsets.only(bottom: 2)),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabs.index,
        children: [
          OverviewTab(goTo: _tabs.animateTo),
          const ListenersTab(),
          const PlacesTab(),
          _MessagesTab(key: _messages),
          UpdatesTab(onRemind: _remind, webPanel: web),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- sign in

class _SignIn extends StatefulWidget {
  final VoidCallback onDone;
  const _SignIn({required this.onDone});

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AdminService>().signIn(_email.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Samgeet admin')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            'Sign in as admin',
            style: TextStyle(fontFamily: kDisplay, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use the admin email and password from the web panel. You stay signed in on this phone for 12 hours.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Admin email', prefixIcon: Icon(Icons.mail_outline_rounded)),
          ),
          const SizedBox(height: 12),
          PasswordField(controller: _pass, label: 'Admin password', error: _error, action: TextInputAction.done, onSubmitted: (_) => _go()),
          const SizedBox(height: 22),
          Center(
            child: GradientButton(label: _busy ? 'Signing in…' : 'Sign in', icon: Icons.lock_open_rounded, onTap: _busy ? null : _go),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- composer

/// Writing a message: from scratch, as a copy of an old one ([from]), or as an update reminder.
class ComposePage extends StatefulWidget {
  final SentMessage? from;
  final bool updateReminder;
  const ComposePage({super.key, this.from, this.updateReminder = false});

  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _image = TextEditingController();
  final _label = TextEditingController();
  final _value = TextEditingController();
  String _style = 'celebrate', _show = 'both', _who = 'all', _action = 'none';
  bool _sending = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _image, _label, _value]) {
      c.addListener(() => setState(() {}));
    }
    final m = widget.from;
    if (m != null) {
      final d = m.toDraft();
      _title.text = d['title'] as String;
      _body.text = d['body'] as String;
      _image.text = d['image_url'] as String;
      _label.text = d['action_label'] as String;
      _value.text = d['action_value'] as String;
      _style = _styles.containsKey(m.style) ? m.style : 'info';
      _show = _showAs.containsKey(m.showAs) ? m.showAs : 'both';
      _who = _audience.containsKey(d['audience']) ? d['audience'] as String : 'all';
      _action = _actions.containsKey(m.action) ? m.action : 'none';
      _note = 'Copy of “${m.title}”. Sending makes a new message; the old one stays as it was.';
    }
    if (widget.updateReminder) {
      _action = 'update';
      _who = 'outdated';
      _label.text = 'Update now';
      _loadReminder();
    }
  }

  Future<void> _loadReminder() async {
    final page = await context.read<AdminService>().history(tab: 'update');
    if (!mounted || page == null) return;
    final r = page.reminder;
    setState(() {
      if (_title.text.isEmpty) _title.text = r.s('title');
      if (_body.text.isEmpty) _body.text = r.s('body');
      _note = r.s('version').isEmpty
          ? 'No version is published yet.'
          : 'Goes only to apps older than ${r.s('version')} (about ${fmt(r.i('behind'))} active phones). Edit the words if you like.';
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _image, _label, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      toast(context, 'Add a title and a message first');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send to ${_audience[_who]!.toLowerCase()}?'),
        content: Text(
          '“${_title.text.trim()}” goes out as ${_showAs[_show]!.toLowerCase()}. Phones get it when the app opens, or within 30 minutes while it runs.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    final err = await context.read<AdminService>().send({
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'image_url': _image.text.trim(),
      'style': _style,
      'show_as': _show,
      'audience': _who,
      'button': _action,
      'action_label': _label.text.trim(),
      'action_value': _value.text.trim(),
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      toast(context, err);
      return;
    }
    toast(context, 'Sent to ${_audience[_who]!.toLowerCase()}');
    Navigator.pop(context, true);
  }

  Widget _chips(Map<String, String> options, String value, ValueChanged<String> onPick) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [for (final e in options.entries) GlassChip(dense: true, label: e.value, selected: value == e.key, onTap: () => setState(() => onPick(e.key)))],
  );

  Widget _caption(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.updateReminder ? 'Update reminder' : (widget.from != null ? 'Edit as new' : 'New message'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          if (_note != null)
            GlassBox(
              radius: 16,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_note!, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message'),
          ),
          TextField(
            controller: _image,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Picture link (optional, https)', prefixIcon: Icon(Icons.image_outlined)),
          ),
          _caption('LOOK'),
          _chips(_styles, _style, (v) => _style = v),
          _caption('SHOW AS'),
          _chips(_showAs, _show, (v) => _show = v),
          _caption('WHO GETS IT'),
          _chips(_audience, _who, (v) => _who = v),
          _caption('BUTTON'),
          _chips(_actions, _action, (v) => _action = v),
          const SizedBox(height: 10),
          TextField(
            controller: _label,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Button text (optional)'),
          ),
          if (_action == 'url' || _action == 'search')
            TextField(
              controller: _value,
              keyboardType: _action == 'url' ? TextInputType.url : TextInputType.text,
              decoration: InputDecoration(labelText: _action == 'url' ? 'Link (https://…)' : 'Search for'),
            ),
          _caption('HOW IT LOOKS'),
          MessagePreview(
            title: _title.text.trim().isEmpty ? 'Title' : _title.text.trim(),
            body: _body.text.trim().isEmpty ? 'Your message' : _body.text.trim(),
            image: _image.text.trim().startsWith('https://') ? _image.text.trim() : '',
            style: _style,
            button: _label.text.trim().isNotEmpty
                ? _label.text.trim()
                : switch (_action) {
                    'update' => 'Update now',
                    'search' => 'Search',
                    'url' => 'Open',
                    _ => 'Got it',
                  },
          ),
          const SizedBox(height: 24),
          Center(
            child: GradientButton(label: _sending ? 'Sending…' : 'Send', expand: true, icon: Icons.send_rounded, onTap: _sending ? null : _send),
          ),
        ],
      ),
    );
  }
}

/// The message card as listeners see it (same look as the popup).
class MessagePreview extends StatelessWidget {
  final String title, body, image, style, button;
  final bool compact;
  const MessagePreview({
    super.key,
    required this.title,
    required this.body,
    required this.image,
    required this.style,
    required this.button,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _headerColors(style);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: compact ? 110 : 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: image.isNotEmpty
                    ? Artwork(image, radius: 0, cacheSize: 800)
                    : Center(
                        child: Container(
                          width: 62,
                          height: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                          ),
                          child: Text(_iconFor(style), style: const TextStyle(fontSize: 28)),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: colors[1].withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      'FROM SAMGEET',
                      style: TextStyle(color: Color.lerp(colors[1], Colors.white, 0.45), fontWeight: FontWeight.w800, fontSize: 10.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(fontFamily: kDisplay, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    maxLines: compact ? 3 : null,
                    overflow: compact ? TextOverflow.ellipsis : null,
                    style: const TextStyle(color: Color(0xFFD9D9E6), height: 1.45, fontSize: 13.5),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      decoration: BoxDecoration(gradient: moodPalette(context).gradient, borderRadius: BorderRadius.circular(30)),
                      child: Text(button, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- messages

class _MessagesTab extends StatefulWidget {
  const _MessagesTab({super.key});

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> with AutomaticKeepAliveClientMixin {
  final List<SentMessage> _items = [];
  String _tab = 'all';
  J _counts = J.empty, _reminder = J.empty;
  bool _split = false, _loading = false, _done = false, _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _items.clear();
      _done = false;
    });
    await _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final page = await context.read<AdminService>().history(before: _items.isEmpty ? null : _items.last.id, tab: _tab);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page == null) {
        _failed = true;
      } else {
        _items.addAll(page.items);
        _counts = page.counts;
        _reminder = page.reminder;
        _split = page.split;
        if (page.items.length < 30) _done = true;
      }
    });
  }

  Future<void> _open(SentMessage m) async {
    final changed = await pushPage<bool>(context, MessagePage(message: m));
    if (changed == true) reload();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tabs = {
      for (final e in _tabs.entries)
        if (_split || (e.key != 'web' && e.key != 'app')) e.key: e.value,
    };
    return RefreshIndicator(
      onRefresh: reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _more();
          return false;
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            GradientButton(
              label: 'New message',
              icon: Icons.edit_rounded,
              expand: true,
              onTap: () async {
                final sent = await pushPage<bool>(context, const ComposePage());
                if (sent == true) reload();
              },
            ),
            const SizedBox(height: 12),
            if (_reminder.i('behind') > 0) ...[
              GlassBox(
                radius: 20,
                tint: AppColors.pink.withValues(alpha: 0.12),
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${fmt(_reminder.i('behind'))} phones aren\'t on ${_reminder.s('version')}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          const Text('Remind only them to update.', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final sent = await pushPage<bool>(context, const ComposePage(updateReminder: true));
                        if (sent == true) reload();
                      },
                      child: const Text('Remind', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in tabs.entries) ...[
                    GlassChip(
                      dense: true,
                      label: _counts[e.key] == null ? e.value : '${e.value} ${fmt(_counts.i(e.key))}',
                      selected: _tab == e.key,
                      onTap: () {
                        setState(() => _tab = e.key);
                        reload();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty && _loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_items.isEmpty && _failed)
              const EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load messages', message: 'Check your connection and pull to try again.'),
            if (_items.isEmpty && !_loading && !_failed)
              const EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'Nothing here yet',
                message: 'Messages show up here with how many people opened them.',
              ),
            for (final m in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Pressable(
                  onTap: () => _open(m),
                  child: GlassBox(
                    radius: 20,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Thumb(m),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  m.active ? const Tag('live', color: kGreen) : const Tag('stopped'),
                                  if (m.source == 'app') const Tag('from the app', color: kViolet),
                                  if (m.isUpdateReminder) const Tag('update reminder', color: AppColors.pink),
                                  if (m.followUp != null) const Tag('follow-up', color: kAmber),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                m.body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFFC9C9D8), fontSize: 13, height: 1.35),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${ago(m.sentAt)} · ${m.audienceLabel} · ${plural(m.delivered, 'phone')} · ${m.openedPct}% opened',
                                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_loading && _items.isNotEmpty)
              const Center(
                child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final SentMessage m;
  const _Thumb(this.m);

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      width: 54,
      height: 54,
      child: m.image.isNotEmpty
          ? Artwork(m.image, radius: 0, cacheSize: 200)
          : DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: _headerColors(m.style))),
              child: Center(child: Text(_iconFor(m.style), style: const TextStyle(fontSize: 22))),
            ),
    ),
  );
}

/// One sent message: how it did, and sending it again to everyone or only part of its audience.
/// Pops true when something changed.
class MessagePage extends StatefulWidget {
  final SentMessage message;
  const MessagePage({super.key, required this.message});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  J? _counts;
  bool _split = true;

  @override
  void initState() {
    super.initState();
    context.read<AdminService>().message(widget.message.id).then((r) {
      if (!mounted || r == null) return;
      setState(() {
        _counts = r.o('follow_ups');
        _split = r.b('split');
      });
    });
  }

  Future<void> _resend(String who) async {
    final m = widget.message;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send it again?'),
        content: Text(
          '“${m.title}” goes out as a new message to: ${_followUps[who]!.$1.toLowerCase()}'
          '${_counts == null ? '' : ' (about ${fmt(_counts!.i(who))} phones)'}. This one stops, so nobody gets it twice, and keeps its numbers.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await context.read<AdminService>().resend(m.id, who: who);
    if (!mounted) return;
    toast(context, err ?? 'Sent again');
    if (err == null) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final admin = context.read<AdminService>();
    final options = [if (m.isUpdateReminder) 'outdated', 'missed', 'unopened', 'all'];
    return Scaffold(
      appBar: AppBar(title: Text('#${m.id}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          MessagePreview(
            title: m.title,
            body: m.body,
            image: m.image,
            style: m.style,
            button: m.actionLabel.isNotEmpty ? m.actionLabel : (m.action == 'none' || _actions[m.action] == null ? 'Got it' : _actions[m.action]!),
          ),
          const SizedBox(height: 12),
          AdminPanel(
            title: 'How it did',
            child: Column(
              children: [
                _Stats(m: m),
                const SizedBox(height: 6),
                FactRow('Sent', '${ago(m.sentAt)}${m.source == 'app' ? ' · from the app' : ''}'),
                FactRow('To', m.audienceLabel),
                FactRow('Shown as', _showAs[m.showAs] ?? m.showAs),
                FactRow('Status', m.active ? 'Live' : 'Stopped'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AdminPanel(
            title: 'Send it again',
            note: 'as a new message',
            child: Column(
              children: [
                for (final who in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassBox(
                      radius: 16,
                      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_followUps[who]!.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text(_followUps[who]!.$2, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.3)),
                                const SizedBox(height: 4),
                                Text(
                                  _counts == null ? '…' : '${fmt(_counts!.i(who))} phones',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          if ((who == 'missed' || who == 'unopened') && !_split)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Needs a\nserver update',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                            )
                          else
                            IconButton.filledTonal(onPressed: () => _resend(who), icon: const Icon(Icons.send_rounded, size: 18)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final sent = await pushPage<bool>(context, ComposePage(from: m));
              if (sent == true && context.mounted) Navigator.pop(context, true);
            },
            icon: const Icon(Icons.edit_rounded),
            label: const Text('Edit as a new message'),
          ),
          TextButton(
            onPressed: () async {
              final done = await admin.toggle(m.id);
              if (!context.mounted) return;
              toast(context, done ? (m.active ? 'Stopped' : 'Sending again') : 'Couldn\'t change it. Try again.');
              if (done) Navigator.pop(context, true);
            },
            child: Text(m.active ? 'Stop sending this one' : 'Start sending it again'),
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final SentMessage m;
  const _Stats({required this.m});

  @override
  Widget build(BuildContext context) {
    final d = m.delivered;
    final silent = (d - m.opened - m.dismissed).clamp(0, d);
    Widget row(String label, int n, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(color: AppColors.muted)),
              ),
              Text('$n${d > 0 && label != 'Reached' ? '  ·  ${(100 * n / d).round()}%' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: d == 0 ? 0 : n / d, minHeight: 7, color: color, backgroundColor: Colors.white10),
          ),
        ],
      ),
    );
    return Column(
      children: [
        row('Reached', d, AppColors.pink),
        row('Opened', m.opened, const Color(0xFFE0823F)),
        row('Closed', m.dismissed, const Color(0xFF5B6B9A)),
        row('No answer yet', silent, Colors.white38),
      ],
    );
  }
}
