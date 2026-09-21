import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// What we know about the device a profile was saved on, kept only if the
/// listener agreed to share it.
///
/// Location is deliberately coarse: coordinates are rounded to two decimals
/// (about 1 km) and only the city, region and country are kept alongside.
/// The IP address is not read here: the app cannot see its own public IP, so
/// it is recorded by the server from the request once accounts go online.
class DeviceSnapshot {
  final String deviceName;
  final String platform;
  final String osVersion;
  final String city;
  final String region;
  final String country;
  final double? lat;
  final double? lng;
  final int capturedAt;

  const DeviceSnapshot({
    required this.deviceName,
    required this.platform,
    this.osVersion = '',
    this.city = '',
    this.region = '',
    this.country = '',
    this.lat,
    this.lng,
    required this.capturedAt,
  });

  bool get hasLocation => lat != null && lng != null;

  Map<String, dynamic> toJson() => {
        'deviceName': deviceName,
        'platform': platform,
        'osVersion': osVersion,
        'city': city,
        'region': region,
        'country': country,
        'lat': lat,
        'lng': lng,
        'capturedAt': capturedAt,
      };

  factory DeviceSnapshot.fromJson(Map<String, dynamic> j) => DeviceSnapshot(
        deviceName: '${j['deviceName'] ?? ''}',
        platform: '${j['platform'] ?? ''}',
        osVersion: '${j['osVersion'] ?? ''}',
        city: '${j['city'] ?? ''}',
        region: '${j['region'] ?? ''}',
        country: '${j['country'] ?? ''}',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        capturedAt: (j['capturedAt'] as num?)?.toInt() ?? 0,
      );

  /// Reads the device name and, if the listener allows it, an approximate
  /// location. Never throws: anything that fails is simply left blank.
  static Future<DeviceSnapshot> capture() async {
    var name = '';
    var os = '';
    try {
      final info = DeviceInfoPlugin();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final a = await info.androidInfo;
          name = '${a.manufacturer} ${a.model}'.trim();
          os = 'Android ${a.version.release}';
        case TargetPlatform.iOS:
          final i = await info.iosInfo;
          name = i.name;
          os = '${i.systemName} ${i.systemVersion}';
        case TargetPlatform.windows:
          final w = await info.windowsInfo;
          name = w.computerName;
          os = 'Windows';
        case TargetPlatform.macOS:
          final m = await info.macOsInfo;
          name = m.computerName;
          os = 'macOS ${m.osRelease}';
        case TargetPlatform.linux:
          final l = await info.linuxInfo;
          name = l.prettyName;
          os = 'Linux';
        case TargetPlatform.fuchsia:
          break;
      }
    } catch (_) {}

    double? lat, lng;
    var city = '', region = '', country = '';
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
          final pos = await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low)).timeout(const Duration(seconds: 8));
          lat = double.parse(pos.latitude.toStringAsFixed(2));
          lng = double.parse(pos.longitude.toStringAsFixed(2));
          try {
            final marks = await Geocoding().placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 5));
            final p = marks.firstOrNull;
            city = p?.locality ?? '';
            region = p?.administrativeArea ?? '';
            country = p?.country ?? '';
          } catch (_) {}
        }
      }
    } catch (_) {}

    return DeviceSnapshot(
      deviceName: name,
      platform: defaultTargetPlatform.name,
      osVersion: os,
      city: city,
      region: region,
      country: country,
      lat: lat,
      lng: lng,
      capturedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
