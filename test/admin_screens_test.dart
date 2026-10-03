import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:samgeet/data/admin_service.dart';
import 'package:samgeet/data/api_client.dart';
import 'package:samgeet/ui/mood_theme.dart';
import 'package:samgeet/ui/screens/admin/admin_reports.dart';
import 'package:samgeet/ui/screens/admin_screen.dart';
import 'package:samgeet/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only the colours; the real controller needs the music player.
class _Mood extends ChangeNotifier implements MoodController {
  @override
  MoodPalette palette = MoodPalette.brand;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Every admin screen, drawn on a phone-sized screen with real answers from the server (saved from a
/// local copy filled with made-up listeners: test/fixtures/admin). Catches layouts that overflow or
/// break on real data.
void main() {
  final fixtures = {
    for (final f in Directory('test/fixtures/admin').listSync().whereType<File>()) f.uri.pathSegments.last.replaceAll('.json', ''): f.readAsStringSync(),
  };
  final calls = <String>[];

  Future<Widget> app(Widget home) async {
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    SharedPreferences.setMockInitialValues({AdminService.tokenPref: '1.$exp.${'a' * 64}', AdminService.expiresPref: exp});
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient(
      prefs,
      base: 'https://x.test/abc/samgeet/api',
      appKey: 'k' * 32,
      deviceInfo: () async => {},
      client: MockClient((r) async {
        final action = (jsonDecode(r.body) as Map)['action'] as String;
        calls.add(action);
        return http.Response.bytes(utf8.encode(fixtures[action] ?? '{"ok":true}'), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    return MultiProvider(
      providers: [
        Provider.value(value: AdminService(prefs, api)),
        ChangeNotifierProvider<MoodController>.value(value: _Mood()),
      ],
      child: MaterialApp(theme: buildTheme(), home: home),
    );
  }

  Future<void> phone(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
  }

  /// Scrolls the first list down to the end, so every row gets built and laid out.
  Future<void> scrollAll(WidgetTester t) async {
    for (var i = 0; i < 12; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -700), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('every section of the admin opens and lays out', (t) async {
    await phone(t);
    await t.pumpWidget(await app(const AdminScreen()));
    await t.pumpAndSettle();
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Listeners'), findsWidgets);
    await scrollAll(t);
    for (final tab in ['Listeners', 'Places', 'Messages', 'Updates']) {
      await t.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)));
      await t.pumpAndSettle();
      await scrollAll(t);
    }
    expect(calls, containsAll(['overview', 'listening', 'users', 'places', 'list', 'releases']));
  });

  testWidgets('a listener, a city, a message and the composer lay out', (t) async {
    await phone(t);
    for (final page in <Widget>[
      const ListenerPage(id: 1, name: 'Sambit Maity'),
      const PlacePage(city: 'Kolkata', country: 'India'),
      MessagePage(message: SentMessage.fromJson(jsonDecode(fixtures['list']!)['notifications'][0])!),
      const ComposePage(updateReminder: true),
    ]) {
      await t.pumpWidget(await app(page));
      await t.pumpAndSettle();
      await scrollAll(t);
    }
    expect(calls, containsAll(['user', 'place', 'message']));
    expect(find.text('Update reminder'), findsOneWidget);
  });
}
