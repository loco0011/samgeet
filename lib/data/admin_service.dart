import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// A JSON object from the admin API with typed, forgiving getters (missing or wrong types give a
/// default instead of throwing), so screens read like `u.s('name')`, `u.i('plays')`.
class J {
  final Map<String, dynamic> raw;
  const J(this.raw);
  static const empty = J({});

  Object? operator [](String k) => raw[k];
  String s(String k) => raw[k] == null ? '' : '${raw[k]}';
  int i(String k) => switch (raw[k]) {
    final int v => v,
    final num v => v.round(),
    final String v => int.tryParse(v) ?? 0,
    _ => 0,
  };
  double d(String k) => switch (raw[k]) {
    final num v => v.toDouble(),
    final String v => double.tryParse(v) ?? 0,
    _ => 0,
  };
  bool b(String k) => raw[k] == true;
  J o(String k) => raw[k] is Map ? J(Map<String, dynamic>.from(raw[k] as Map)) : empty;
  List<J> list(String k) => [
    for (final x in raw[k] is List ? raw[k] as List : const [])
      if (x is Map) J(Map<String, dynamic>.from(x)),
  ];
  List<num> nums(String k) => [for (final x in raw[k] is List ? raw[k] as List : const []) x is num ? x : 0];

  /// A UTC "YYYY-MM-DD HH:MM:SS" from the server, as local time.
  DateTime? time(String k) =>
      raw[k] is String && (raw[k] as String).isNotEmpty ? DateTime.tryParse('${(raw[k] as String).replaceFirst(' ', 'T')}Z')?.toLocal() : null;

  /// [now, previous] pairs the overview uses for the change against the period before.
  (num, num?) pair(String k) {
    final v = raw[k];
    if (v is List && v.isNotEmpty) return (v[0] is num ? v[0] as num : 0, v.length > 1 && v[1] is num ? v[1] as num : null);
    return (0, null);
  }
}

/// A message as the admin sees it: what was sent, and how it did.
class SentMessage {
  final int id;
  final String title;
  final String body;
  final String image;
  final String style; // info | celebrate | warning
  final String action; // none | url | update | search
  final String actionValue;
  final String actionLabel;
  final String showAs; // both | popup | system
  final String audience; // all | signed_in | guests | below_build
  final String audienceLabel;
  final String source; // web | app
  final String? followUp; // missed | unopened, for re-sends to part of an audience
  final bool active;
  final DateTime sentAt;
  final int delivered;
  final int opened;
  final int dismissed;

  const SentMessage({
    required this.id,
    required this.title,
    required this.body,
    this.image = '',
    this.style = 'info',
    this.action = 'none',
    this.actionValue = '',
    this.actionLabel = '',
    this.showAs = 'both',
    this.audience = 'all',
    this.audienceLabel = 'Everyone',
    this.source = 'web',
    this.followUp,
    this.active = true,
    required this.sentAt,
    this.delivered = 0,
    this.opened = 0,
    this.dismissed = 0,
  });

  bool get isUpdateReminder => action == 'update';
  int get openedPct => delivered == 0 ? 0 : (100 * opened / delivered).round();

  static SentMessage? fromJson(Object? j) {
    if (j is! Map || j['id'] is! int) return null;
    final x = J(Map<String, dynamic>.from(j));
    return SentMessage(
      id: x.i('id'),
      title: x.s('title'),
      body: x.s('body'),
      image: x.s('image'),
      style: x.s('style'),
      action: x.s('action'),
      actionValue: x.s('action_value'),
      actionLabel: x.s('action_label'),
      showAs: x.s('show_as'),
      audience: x.s('audience'),
      audienceLabel: x.s('audience_label').isEmpty ? 'Everyone' : x.s('audience_label'),
      source: x.s('source').isEmpty ? 'web' : x.s('source'),
      followUp: x['follow_up'] is String ? x.s('follow_up') : null,
      active: x.b('active'),
      sentAt: DateTime.fromMillisecondsSinceEpoch(x.i('sent_at') * 1000),
      delivered: x.i('delivered'),
      opened: x.i('opened'),
      dismissed: x.i('dismissed'),
    );
  }

  Map<String, Object> toDraft() => {
    'title': title, 'body': body, 'image_url': image, 'style': style, 'button': action, //
    'action_value': actionValue, 'action_label': actionLabel, 'show_as': showAs,
    'audience': audience == 'below_build' ? (action == 'update' ? 'outdated' : 'all') : audience,
  };
}

/// One page of the message history, with the counts for each tab and the update reminder.
class MessageHistory {
  final List<SentMessage> items;
  final J counts;
  final bool split; // the server can tell web from app messages
  final J reminder; // version, behind, title, body
  const MessageHistory(this.items, this.counts, this.split, this.reminder);
}

/// Samgeet's admin tools inside the app (`backend/samgeet/api/admin.php`): the same reports as the
/// web panel, plus sending messages.
///
/// Needs the admin email and password (the same as the web panel). Signing in gives a pass that
/// lasts 12 hours and is kept on this phone only; it stops working if the admin password changes.
class AdminService {
  static const tokenPref = 'adminToken';
  static const expiresPref = 'adminExpires';

  final SharedPreferences _prefs;
  final ApiClient api;
  AdminService(this._prefs, this.api);

  bool get signedIn {
    final exp = _prefs.getInt(expiresPref) ?? 0;
    return _prefs.getString(tokenPref) != null && exp * 1000 > DateTime.now().millisecondsSinceEpoch;
  }

  /// The web panel's address (the API folder's sibling), or null in builds without a server.
  String? get webPanel {
    final base = api.base;
    if (base.isEmpty) return null;
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b.endsWith('/api') ? '${b.substring(0, b.length - 4)}/admin/' : null;
  }

  Future<void> signOut() async {
    await _prefs.remove(tokenPref);
    await _prefs.remove(expiresPref);
  }

  /// Null when signed in, else what went wrong, in words.
  Future<String?> signIn(String email, String password) async {
    final r = await api.post('admin', {'action': 'login', 'email': email.trim().toLowerCase(), 'password': password});
    if (r == null) return 'No connection to Samgeet\'s server.';
    if (r.status == 429) return 'Too many wrong tries. Wait 15 minutes.';
    if (r.status == 403) return 'Wrong email or password.';
    if (!r.ok || r.json['token'] is! String) return 'Something went wrong. Try again.';
    await _prefs.setString(tokenPref, r.json['token'] as String);
    await _prefs.setInt(expiresPref, (r.json['expires'] as num).toInt());
    return null;
  }

  Future<ApiResponse?> _call(Map<String, dynamic> body) async {
    final r = await api.post('admin', body, headers: {'X-Samgeet-Admin': _prefs.getString(tokenPref) ?? ''});
    if (r?.status == 401) await signOut(); // the pass ran out or the password changed
    return r;
  }

  /// A report ([action] with [args]), or null when offline or it failed.
  Future<J?> report(String action, [Map<String, dynamic> args = const {}]) async {
    final r = await _call({'action': action, ...args});
    return r != null && r.ok ? J(r.json) : null;
  }

  Future<J?> overview(String range) => report('overview', {'r': range});
  Future<J?> listening(String range) => report('listening', {'r': range});
  Future<J?> users({String filter = 'all', String q = '', String sort = 'recent', int page = 1}) =>
      report('users', {'filter': filter, 'q': q, 'sort': sort, 'page': page});
  Future<J?> user(int id) => report('user', {'id': id});
  Future<J?> places() => report('places');
  Future<J?> place(String city, String country) => report('place', {'city': city, 'country': country});
  Future<J?> releases() => report('releases');
  Future<J?> message(int id) => report('message', {'id': id});

  Future<bool> signOutUser(int id) async => (await _call({'action': 'user_signout', 'id': id}))?.ok ?? false;
  Future<bool> toggleBlock(int id) async => (await _call({'action': 'user_block', 'id': id}))?.ok ?? false;
  Future<bool> toggleRelease(int id) async => (await _call({'action': 'release_toggle', 'id': id}))?.ok ?? false;

  /// Sent messages, newest first, 30 at a time ([before] = the last id already shown).
  Future<MessageHistory?> history({int? before, String tab = 'all'}) async {
    final r = await _call({'action': 'list', 'before': ?before, 'tab': tab});
    if (r == null || !r.ok) return null;
    final j = J(r.json);
    final list = r.json['notifications'];
    return MessageHistory([for (final x in list is List ? list : const []) ?SentMessage.fromJson(x)], j.o('counts'), j.b('split'), j.o('reminder'));
  }

  /// Sends a new message. Null when sent, else the problem in words.
  Future<String?> send(Map<String, Object> draft) async {
    final r = await _call({'action': 'send', ...draft});
    if (r == null) return 'No connection to Samgeet\'s server.';
    if (r.ok) return null;
    return _problem(r.error);
  }

  /// Sends an old message again as a new one to [who] (all | missed | unopened | outdated). The
  /// original stops but keeps its numbers. Null when sent, else the problem in words.
  Future<String?> resend(int id, {String who = 'all'}) async {
    final r = await _call({'action': 'resend', 'id': id, 'who': who});
    if (r == null) return 'No connection to Samgeet\'s server.';
    if (r.ok) return null;
    return _problem(r.error);
  }

  /// Stops a live message, or lets a stopped one go out again.
  Future<bool> toggle(int id) async => (await _call({'action': 'toggle', 'id': id}))?.ok ?? false;

  String _problem(String? code) => switch (code) {
    'bad_text' => 'Add a title (up to 120 characters) and a message.',
    'bad_link' => 'The button link must start with https://',
    'bad_search' => 'Add what the button should search for.',
    'bad_image' => 'The picture link must start with https://',
    'no_release' => 'No version is published yet, so nobody is out of date.',
    'needs_update' => 'The server needs its database update first (see the web panel).',
    'admin_session' => 'Your admin sign-in ran out. Sign in again.',
    _ => 'Couldn\'t send it. Try again.',
  };
}
