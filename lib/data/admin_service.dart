import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

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
    this.active = true,
    required this.sentAt,
    this.delivered = 0,
    this.opened = 0,
    this.dismissed = 0,
  });

  static SentMessage? fromJson(Object? j) {
    if (j is! Map || j['id'] is! int) return null;
    String s(String k) => '${j[k] ?? ''}';
    int n(String k) => j[k] is int ? j[k] as int : 0;
    return SentMessage(
      id: j['id'] as int,
      title: s('title'),
      body: s('body'),
      image: s('image'),
      style: s('style'),
      action: s('action'),
      actionValue: s('action_value'),
      actionLabel: s('action_label'),
      showAs: s('show_as'),
      audience: s('audience'),
      active: j['active'] == true,
      sentAt: DateTime.fromMillisecondsSinceEpoch(n('sent_at') * 1000),
      delivered: n('delivered'),
      opened: n('opened'),
      dismissed: n('dismissed'),
    );
  }

  Map<String, Object> toDraft() => {
        'title': title, 'body': body, 'image_url': image, 'style': style, 'button': action, //
        'action_value': actionValue, 'action_label': actionLabel, 'show_as': showAs,
        'audience': audience == 'below_build' ? 'all' : audience,
      };
}

/// Sending messages to everyone from inside the app (`backend/samgeet/api/admin.php`).
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

  /// Sent messages, newest first, 30 at a time ([before] = the last id already shown).
  Future<List<SentMessage>?> history({int? before}) async {
    final r = await _call({'action': 'list', 'before': ?before});
    if (r == null || !r.ok) return null;
    final list = r.json['notifications'];
    return [for (final j in list is List ? list : const []) ?SentMessage.fromJson(j)];
  }

  /// Sends a new message. Null when sent, else the problem in words.
  Future<String?> send(Map<String, Object> draft) async {
    final r = await _call({'action': 'send', ...draft});
    if (r == null) return 'No connection to Samgeet\'s server.';
    if (r.ok) return null;
    return switch (r.error) {
      'bad_text' => 'Add a title (up to 120 characters) and a message.',
      'bad_link' => 'The button link must start with https://',
      'bad_search' => 'Add what the button should search for.',
      'bad_image' => 'The picture link must start with https://',
      'admin_session' => 'Your admin sign-in ran out. Sign in again.',
      _ => 'Couldn\'t send it. Try again.',
    };
  }

  /// Sends an old message again as a new one; the original stays as it was.
  Future<bool> resend(int id) async => (await _call({'action': 'resend', 'id': id}))?.ok ?? false;

  /// Stops a live message, or lets a stopped one go out again.
  Future<bool> toggle(int id) async => (await _call({'action': 'toggle', 'id': id}))?.ok ?? false;
}
