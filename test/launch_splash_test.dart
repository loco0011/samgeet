import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/ui/widgets/launch_splash.dart';

void main() {
  testWidgets('the launch logo animates without any text, then gets out of the way', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LaunchSplash(child: Text('the app'))));
    expect(find.byType(Image), findsOneWidget); // the logo, over the app
    expect(find.text('Samgeet'), findsNothing);

    for (var i = 0; i < 200 && find.byType(Image).evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(Image), findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a tap skips to the end', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LaunchSplash(child: Text('the app'))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(Image));
    // Only the zoom-out is left: under half a second, well short of the full 1.9 s.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(Image), findsNothing);
  });
}
