import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/engine/mood.dart';

void main() {
  late DateTime now;
  MoodMomentum make({Mood? current}) => MoodMomentum(current: current, now: () => now);

  setUp(() => now = DateTime(2026, 9, 23, 20));

  test('changes once 3 of the last 5 songs share a mood', () {
    final m = make();
    expect(m.played(Mood.romantic), isFalse);
    expect(m.played(Mood.party), isFalse);
    expect(m.played(Mood.romantic), isFalse);
    expect(m.played(Mood.romantic), isTrue);
    expect(m.current, Mood.romantic);
  });

  test('one odd song in between does not reset the count', () {
    final m = make();
    m.played(Mood.sad);
    m.played(null);
    m.played(Mood.sad);
    expect(m.played(Mood.sad), isTrue);
  });

  test('holds the colours for 5 minutes after a change', () {
    final m = make();
    for (var i = 0; i < 3; i++) {
      m.played(Mood.party);
    }
    expect(m.current, Mood.party);
    now = now.add(const Duration(minutes: 2));
    for (var i = 0; i < 5; i++) {
      expect(m.played(Mood.chill), isFalse);
    }
    expect(m.current, Mood.party);
    now = now.add(const Duration(minutes: 4));
    expect(m.played(Mood.chill), isTrue);
    expect(m.current, Mood.chill);
  });

  test('songs without a clear mood keep the current colours', () {
    final m = make(current: Mood.devotional);
    for (var i = 0; i < 6; i++) {
      expect(m.played(null), isFalse);
    }
    expect(m.current, Mood.devotional);
  });
}
