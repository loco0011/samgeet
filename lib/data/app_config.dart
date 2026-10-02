import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';
import 'api_client.dart';
import 'update_service.dart';

/// A message sent from the admin panel.
class Announcement {
  final int id;
  final String title;
  final String body;
  final String image; // https picture, or ''
  final String style; // info | celebrate | warning
  final String action; // none | url | update | search
  final String actionValue;
  final String actionLabel;
  final String showAs; // popup | system | both

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.image = '',
    this.style = 'info',
    this.action = 'none',
    this.actionValue = '',
    this.actionLabel = '',
    this.showAs = 'both',
  });

  static Announcement? fromJson(Object? j) {
    if (j is! Map || j['id'] is! int) return null;
    String s(String k) => '${j[k] ?? ''}'.trim();
    final image = s('image');
    return Announcement(
      id: j['id'] as int,
      title: s('title'),
      body: s('body'),
      image: image.startsWith('https://') ? image : '',
      style: s('style'),
      action: s('action'),
      actionValue: s('action_value'),
      actionLabel: s('action_label'),
      showAs: s('show_as'),
    );
  }

  Map<String, Object> toJson() => {
        'id': id, 'title': title, 'body': body, 'image': image, 'style': style, 'action': action, //
        'action_value': actionValue, 'action_label': actionLabel, 'show_as': showAs,
      };

  bool get popup => showAs != 'system';
  bool get system => showAs != 'popup';

  String get buttonLabel => actionLabel.isNotEmpty
      ? actionLabel
      : switch (action) {
          'update' => 'Update now',
          'search' => 'Search',
          'url' => 'Open',
          _ => 'Got it',
        };
}

/// What Samgeet's server says when the app opens (`backend/samgeet/api/app.php`): a newer version
/// published from the admin panel, and messages to show. Asked again every 30 minutes while the
/// app runs (it keeps running while music plays), so new messages arrive without a push service.
///
/// Messages meant as a popup show while the app is on screen ([popups]); ones meant for the phone's
/// notification shade go there ([LocalNotifier]), and a tap on one comes back through [taps].
class AppConfig extends ChangeNotifier {
  static const _seenPref = 'notifSeen';

  final SharedPreferences _prefs;
  final ApiClient api;
  final Analytics? analytics;
  final LocalNotifier notifier;

  AppUpdate? update;
  bool loaded = false;

  final _popups = StreamController<Announcement>.broadcast();
  final _taps = StreamController<Announcement>.broadcast();
  final List<Announcement> _waiting = []; // popups that arrived while the app was in the background
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _refreshing = false;

  AppConfig(this._prefs, this.api, {this.analytics, LocalNotifier? notifier}) : notifier = notifier ?? LocalNotifier() {
    this.notifier.onTap = (a) {
      _receipt(a.id, 'opened');
      analytics?.log('notification_open', value: '${a.id}', meta: {'via': 'system'});
      _taps.add(a);
    };
  }

  /// Popups to show now (the app is on screen).
  Stream<Announcement> get popups => _popups.stream;

  /// Phone notifications the listener tapped.
  Stream<Announcement> get taps => _taps.stream;

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  Set<int> get _seen => {for (final s in _prefs.getStringList(_seenPref) ?? const <String>[]) ?int.tryParse(s)};

  Future<void> _markSeen(int id) async {
    final list = [..._seen, id];
    await _prefs.setStringList(_seenPref, [for (final i in list.skip(list.length > 200 ? list.length - 200 : 0)) '$i']);
  }

  /// Asks the server. Returns whether it answered.
  Future<bool> refresh() async {
    if (_refreshing) return loaded;
    _refreshing = true;
    try {
      final r = await api.post('app', {'action': 'config', 'device': await api.deviceInfo()}, timeout: const Duration(seconds: 12));
      if (r == null || !r.ok) return false;
      update = AppUpdate.fromServer(r.json['update']);
      loaded = true;
      notifyListeners();
      final seen = _seen;
      final list = r.json['notifications'];
      for (final a in (list is List ? list : const []).map(Announcement.fromJson).whereType<Announcement>()) {
        if (seen.contains(a.id) || a.title.isEmpty) continue;
        await _markSeen(a.id);
        _deliver(a);
      }
      return true;
    } finally {
      _refreshing = false;
    }
  }

  void _deliver(Announcement a) {
    if (_foreground && a.popup) {
      _popups.add(a);
    } else if (a.system) {
      unawaited(notifier.show(a));
    } else {
      _waiting.add(a);
    }
  }

  /// Call once at startup.
  Future<void> start() async {
    await notifier.init();
    _timer ??= Timer.periodic(const Duration(minutes: 30), (_) => refresh());
    _lifecycle ??= AppLifecycleListener(onResume: () {
      for (final a in _waiting) {
        _popups.add(a);
      }
      _waiting.clear();
    });
  }

  /// The listener closed a popup ([opened] when they pressed its button).
  void closed(Announcement a, {required bool opened}) {
    _receipt(a.id, opened ? 'opened' : 'dismissed');
    analytics?.log(opened ? 'notification_open' : 'notification_dismiss', value: '${a.id}', meta: {'via': 'popup'});
  }

  void _receipt(int id, String what) => unawaited(api.post('app', {'action': 'receipt', 'id': id, 'what': what}));

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    _popups.close();
    _taps.close();
    super.dispose();
  }
}

/// Notifications in the phone's notification shade, for messages from the admin panel.
class LocalNotifier {
  static const _channel = AndroidNotificationChannel(
    'app.samgeet.music.news',
    'News from Samgeet',
    description: 'New features, updates and messages from Samgeet',
    importance: Importance.high,
  );

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called when the listener taps one of these notifications.
  void Function(Announcement)? onTap;

  Future<void> init() async {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
        onDidReceiveNotificationResponse: (r) => _tapped(r.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      _ready = true;
      // Opened by tapping one while the app was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final payload = launch!.notificationResponse?.payload;
        Future.delayed(const Duration(seconds: 2), () => _tapped(payload));
      }
    } catch (e) {
      debugPrint('notifications unavailable: $e');
    }
  }

  void _tapped(String? payload) {
    if (payload == null) return;
    try {
      final a = Announcement.fromJson(jsonDecode(payload));
      if (a != null) onTap?.call(a);
    } catch (_) {}
  }

  /// Asks for permission to show notifications (Android 13 and newer). Returns whether allowed.
  Future<bool> askPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> show(Announcement a) async {
    if (!_ready) return;
    StyleInformation style = BigTextStyleInformation(a.body, contentTitle: a.title);
    if (a.image.isNotEmpty) {
      try {
        final r = await http.get(Uri.parse(a.image)).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200 && r.bodyBytes.length < 3000000) {
          final pic = ByteArrayAndroidBitmap(Uint8List.fromList(r.bodyBytes));
          style = BigPictureStyleInformation(pic, largeIcon: pic, contentTitle: a.title, summaryText: a.body, hideExpandedLargeIcon: true);
        }
      } catch (_) {}
    }
    await _plugin.show(
      id: 1000 + a.id % 100000,
      title: a.title,
      body: a.body,
      payload: jsonEncode(a.toJson()),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFFD0284F),
          styleInformation: style,
        ),
      ),
    );
  }
}
