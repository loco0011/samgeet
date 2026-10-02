import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/admin_service.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/account_widgets.dart';
import '../widgets/common.dart';
import '../widgets/glass.dart';

const _styles = {'info': 'Info', 'celebrate': 'Celebrate', 'warning': 'Warning'};
const _showAs = {'both': 'Popup + notification', 'popup': 'Popup only', 'system': 'Notification only'};
const _audience = {'all': 'Everyone', 'signed_in': 'Signed in', 'guests': 'Guests'};
const _actions = {'none': 'No button link', 'update': 'Update the app', 'url': 'Open a link', 'search': 'Search for…'};

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

/// Samgeet's admin tools inside the app: write a message and send it to everyone, and look back
/// at what was sent and how it did. Opens from Settings (tap the version line 7 times).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _history = GlobalKey<_HistoryState>();
  final _composer = GlobalKey<_ComposerState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.read<AdminService>();
    if (!admin.signedIn) return _SignIn(onDone: () => setState(() {}));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send a message'),
        actions: [
          TextButton(
            onPressed: () async {
              await admin.signOut();
              if (mounted) setState(() {});
            },
            child: const Text('Sign out', style: TextStyle(color: AppColors.muted)),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.pink,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800),
          unselectedLabelColor: AppColors.muted,
          tabs: const [Tab(text: 'New message'), Tab(text: 'History')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _Composer(key: _composer, onSent: () {
          _tabs.animateTo(1);
          _history.currentState?.reload();
        }),
        _History(
          key: _history,
          onEdit: (m) {
            _composer.currentState?.load(m);
            _tabs.animateTo(0);
          },
        ),
      ]),
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
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const Text('Sign in to send messages', style: TextStyle(fontFamily: kDisplay, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
        const SizedBox(height: 6),
        const Text('Use the admin email and password from the web panel. You stay signed in on this phone for 12 hours.',
            style: TextStyle(color: AppColors.muted, height: 1.4)),
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
        Center(child: GradientButton(label: _busy ? 'Signing in…' : 'Sign in', icon: Icons.lock_open_rounded, onTap: _busy ? null : _go)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- composer

class _Composer extends StatefulWidget {
  final VoidCallback onSent;
  const _Composer({super.key, required this.onSent});

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> with AutomaticKeepAliveClientMixin {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _image = TextEditingController();
  final _label = TextEditingController();
  final _value = TextEditingController();
  String _style = 'celebrate', _show = 'both', _who = 'all', _action = 'none';
  String? _copiedFrom;
  bool _sending = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _body, _image, _label, _value]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _image, _label, _value]) {
      c.dispose();
    }
    super.dispose();
  }

  /// "Edit as new": start from an old message. Sending makes a new one; the old one stays.
  void load(SentMessage m) {
    final d = m.toDraft();
    setState(() {
      _title.text = d['title'] as String;
      _body.text = d['body'] as String;
      _image.text = d['image_url'] as String;
      _label.text = d['action_label'] as String;
      _value.text = d['action_value'] as String;
      _style = _styles.containsKey(m.style) ? m.style : 'info';
      _show = _showAs.containsKey(m.showAs) ? m.showAs : 'both';
      _who = _audience.containsKey(d['audience']) ? d['audience'] as String : 'all';
      _action = _actions.containsKey(m.action) ? m.action : 'none';
      _copiedFrom = m.title;
    });
  }

  void _clear() {
    for (final c in [_title, _body, _image, _label, _value]) {
      c.clear();
    }
    setState(() {
      _style = 'celebrate';
      _show = 'both';
      _who = 'all';
      _action = 'none';
      _copiedFrom = null;
    });
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
        content: Text('“${_title.text.trim()}” goes out as ${_showAs[_show]!.toLowerCase()}. Phones get it when the app opens, or within 30 minutes while it runs.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
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
    _clear();
    widget.onSent();
  }

  Widget _chips(Map<String, String> options, String value, ValueChanged<String> onPick) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in options.entries) GlassChip(dense: true, label: e.value, selected: value == e.key, onTap: () => setState(() => onPick(e.key))),
      ]);

  Widget _label2(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.4)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: [
      if (_copiedFrom != null)
        GlassBox(
          radius: 16,
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            const Icon(Icons.copy_all_rounded, size: 18, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text('Copy of “$_copiedFrom”. Sending makes a new message; the old one stays as it was.', style: const TextStyle(fontSize: 12.5, height: 1.35))),
            TextButton(onPressed: _clear, child: const Text('Start blank')),
          ]),
        ),
      const SizedBox(height: 4),
      TextField(controller: _title, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title')),
      TextField(controller: _body, minLines: 3, maxLines: 6, maxLength: 2000, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Message')),
      TextField(controller: _image, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Picture link (optional, https)', prefixIcon: Icon(Icons.image_outlined))),
      _label2('LOOK'),
      _chips(_styles, _style, (v) => _style = v),
      _label2('SHOW AS'),
      _chips(_showAs, _show, (v) => _show = v),
      _label2('WHO GETS IT'),
      _chips(_audience, _who, (v) => _who = v),
      _label2('BUTTON'),
      _chips(_actions, _action, (v) => _action = v),
      const SizedBox(height: 10),
      TextField(controller: _label, maxLength: 40, decoration: const InputDecoration(labelText: 'Button text (optional)')),
      if (_action == 'url' || _action == 'search')
        TextField(
          controller: _value,
          keyboardType: _action == 'url' ? TextInputType.url : TextInputType.text,
          decoration: InputDecoration(labelText: _action == 'url' ? 'Link (https://…)' : 'Search for'),
        ),
      _label2('HOW IT LOOKS'),
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
      Center(child: GradientButton(label: _sending ? 'Sending…' : 'Send to ${_audience[_who]!.toLowerCase()}', icon: Icons.send_rounded, onTap: _sending ? null : _send)),
    ]);
  }
}

/// The message card as listeners see it (same look as the popup).
class MessagePreview extends StatelessWidget {
  final String title, body, image, style, button;
  final bool compact;
  const MessagePreview({super.key, required this.title, required this.body, required this.image, required this.style, required this.button, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = _headerColors(style);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: Colors.white.withValues(alpha: 0.08)), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: compact ? 110 : 150,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: image.isNotEmpty
                  ? Artwork(image, radius: 0, cacheSize: 800)
                  : Center(
                      child: Container(
                        width: 62,
                        height: 62,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.16), border: Border.all(color: Colors.white.withValues(alpha: 0.35))),
                        child: Text(_iconFor(style), style: const TextStyle(fontSize: 28)),
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: colors[1].withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text('FROM SAMGEET', style: TextStyle(color: Color.lerp(colors[1], Colors.white, 0.45), fontWeight: FontWeight.w800, fontSize: 10.5)),
              ),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontFamily: kDisplay, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 6),
              Text(body, maxLines: compact ? 3 : null, overflow: compact ? TextOverflow.ellipsis : null, style: const TextStyle(color: Color(0xFFD9D9E6), height: 1.45, fontSize: 13.5)),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  decoration: BoxDecoration(gradient: moodPalette(context).gradient, borderRadius: BorderRadius.circular(30)),
                  child: Text(button, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- history

class _History extends StatefulWidget {
  final ValueChanged<SentMessage> onEdit;
  const _History({super.key, required this.onEdit});

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> with AutomaticKeepAliveClientMixin {
  final List<SentMessage> _items = [];
  bool _loading = false, _done = false, _failed = false;

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
    final page = await context.read<AdminService>().history(before: _items.isEmpty ? null : _items.last.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (page == null) {
        _failed = true;
      } else {
        _items.addAll(page);
        if (page.length < 30) _done = true;
      }
    });
  }

  Future<void> _open(SentMessage m) async {
    final admin = context.read<AdminService>();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            MessagePreview(
              title: m.title,
              body: m.body,
              image: m.image,
              style: m.style,
              button: m.actionLabel.isNotEmpty ? m.actionLabel : (_actions[m.action] == null || m.action == 'none' ? 'Got it' : _actions[m.action]!),
            ),
            const SizedBox(height: 16),
            _Stats(m: m),
            const SizedBox(height: 8),
            Text('Sent ${_when(m.sentAt)} · ${_audience[m.audience] ?? 'Older app versions'} · ${_showAs[m.showAs] ?? m.showAs}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.pink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () => Navigator.pop(ctx, 'resend'),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Send again', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'edit'), icon: const Icon(Icons.edit_rounded), label: const Text('Edit as a new message')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'toggle'), child: Text(m.active ? 'Stop sending this one' : 'Start sending it again')),
          ]),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        widget.onEdit(m);
      case 'resend':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Send it again?'),
            content: Text('“${m.title}” goes out again as a new message to ${(_audience[m.audience] ?? 'the same people').toLowerCase()}. This one stays in the history as it is.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: () => Navigator.pop(ctx, true), child: const Text('Send again')),
            ],
          ),
        );
        if (ok != true) return;
        final sent = await admin.resend(m.id);
        if (!mounted) return;
        toast(context, sent ? 'Sent again' : 'Couldn\'t send it. Try again.');
        if (sent) reload();
      case 'toggle':
        final done = await admin.toggle(m.id);
        if (!mounted) return;
        toast(context, done ? (m.active ? 'Stopped' : 'Sending again') : 'Couldn\'t change it. Try again.');
        if (done) reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty && _failed) {
      return EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load the history', message: 'Check your connection and pull to try again.');
    }
    if (_items.isEmpty) return const EmptyState(icon: Icons.notifications_none_rounded, title: 'Nothing sent yet', message: 'Messages you send show up here with how many people opened them.');
    return RefreshIndicator(
      onRefresh: reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _more();
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          itemCount: _items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            if (i == _items.length) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Center(child: _loading ? const CircularProgressIndicator() : Text(_done ? '${_items.length} messages' : '', style: const TextStyle(color: AppColors.muted))),
              );
            }
            final m = _items[i];
            return Pressable(
              onTap: () => _open(m),
              child: GlassBox(
                radius: 20,
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 58,
                      height: 58,
                      child: m.image.isNotEmpty
                          ? Artwork(m.image, radius: 0, cacheSize: 200)
                          : DecoratedBox(
                              decoration: BoxDecoration(gradient: LinearGradient(colors: _headerColors(m.style))),
                              child: Center(child: Text(_iconFor(m.style), style: const TextStyle(fontSize: 24))),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const SizedBox(width: 6),
                        _Tag(m.active ? 'live' : 'stopped', m.active),
                      ]),
                      const SizedBox(height: 3),
                      Text(m.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFC9C9D8), fontSize: 13, height: 1.35)),
                      const SizedBox(height: 6),
                      Text('${_when(m.sentAt)} · ${_audience[m.audience] ?? 'Older versions'} · ${plural(m.delivered, 'phone')} · ${m.delivered == 0 ? 0 : (100 * m.opened / m.delivered).round()}% opened',
                          style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final bool on;
  const _Tag(this.text, this.on);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: on ? const Color(0x263FB27F) : Colors.white10, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: on ? const Color(0xFF3FB27F) : AppColors.muted)),
      );
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
              Text('$n${d > 0 && label != 'Reached' ? '  ·  ${(100 * n / d).round()}%' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: d == 0 ? 0 : n / d, minHeight: 7, color: color, backgroundColor: Colors.white10),
            ),
          ]),
        );
    return Column(children: [
      row('Reached', d, AppColors.pink),
      row('Opened', m.opened, const Color(0xFFE0823F)),
      row('Closed', m.dismissed, const Color(0xFF5B6B9A)),
      row('No answer yet', silent, Colors.white38),
    ]);
  }
}

String _when(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${months[t.month - 1]} ${t.year}';
}
