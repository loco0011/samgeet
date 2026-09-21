import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/device_snapshot.dart';
import 'package:samgeet/data/profile.dart';

void main() {
  test('profile keeps consent and device details through a JSON round trip', () {
    final p = Profile(
      name: 'Sam',
      email: 'sam@example.com',
      createdAt: 1,
      shareDeviceInfo: true,
      device: const DeviceSnapshot(deviceName: 'Google Pixel 8', platform: 'android', osVersion: 'Android 15', city: 'Kolkata', country: 'India', lat: 22.57, lng: 88.36, capturedAt: 5),
    );
    final back = Profile.fromJson(p.toJson());
    expect(back.shareDeviceInfo, isTrue);
    expect(back.device?.deviceName, 'Google Pixel 8');
    expect(back.device?.city, 'Kolkata');
    expect(back.device?.hasLocation, isTrue);
  });

  test('profiles saved before device sharing existed load with it switched off', () {
    final back = Profile.fromJson({'name': 'Old', 'email': 'old@example.com', 'createdAt': 1});
    expect(back.shareDeviceInfo, isFalse);
    expect(back.device, isNull);
  });
}
