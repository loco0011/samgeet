import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/update_service.dart';

Map<String, dynamic> release(String tag, {String body = '', bool apk = true}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/loco0011/samgeet/releases/tag/$tag',
      'body': body,
      'assets': [
        if (apk) {'name': 'Samgeet.apk', 'browser_download_url': 'https://github.com/loco0011/samgeet/releases/download/$tag/Samgeet.apk'},
      ],
    };

void main() {
  group('version compare', () {
    test('orders dotted versions numerically', () {
      expect(AppUpdate.compareVersions('1.3.10', '1.3.9'), greaterThan(0));
      expect(AppUpdate.compareVersions('1.4', '1.3.9'), greaterThan(0));
      expect(AppUpdate.compareVersions('1.3.2', '1.3.2'), 0);
      expect(AppUpdate.compareVersions('1.3.1', '1.3.2'), lessThan(0));
    });
  });

  group('AppUpdate.fromRelease', () {
    test('a newer release gives the APK link', () {
      final u = AppUpdate.fromRelease(release('v1.4.0'), current: '1.3.2')!;
      expect(u.version, '1.4.0');
      expect(u.downloadUrl, 'https://github.com/loco0011/samgeet/releases/download/v1.4.0/Samgeet.apk');
      expect(u.required, isFalse);
    });

    test('the same or an older release is not an update', () {
      expect(AppUpdate.fromRelease(release('v1.3.2'), current: '1.3.2'), isNull);
      expect(AppUpdate.fromRelease(release('v1.3.0'), current: '1.3.2'), isNull);
    });

    test('links outside this project on GitHub are never opened', () {
      final evil = {...release('v2.0.0'), 'assets': [
        {'name': 'Samgeet.apk', 'browser_download_url': 'https://evil.example/Samgeet.apk'},
      ]};
      expect(AppUpdate.fromRelease(evil, current: '1.3.2')!.downloadUrl, 'https://github.com/loco0011/samgeet/releases/tag/v2.0.0');
      expect(AppUpdate.isTrustedLink('https://github.com/loco0011/samgeet/releases/download/v2/Samgeet.apk'), isTrue);
      expect(AppUpdate.isTrustedLink('https://github.com/someone/else/releases/download/v2/x.apk'), isFalse);
      expect(AppUpdate.isTrustedLink('http://github.com/loco0011/samgeet/releases/latest'), isFalse);
      expect(AppUpdate.isTrustedLink('javascript:alert(1)'), isFalse);
    });

    test('no APK attached falls back to the release page', () {
      final u = AppUpdate.fromRelease(release('v2.0.0', apk: false), current: '1.3.2')!;
      expect(u.downloadUrl, contains('/releases/tag/v2.0.0'));
    });

    test('[required] in the notes makes it mandatory and is hidden', () {
      final u = AppUpdate.fromRelease(release('v2.0.0', body: '[required]\n- Fixes playback'), current: '1.3.2')!;
      expect(u.required, isTrue);
      expect(u.notes, isNot(contains('required')));
    });

    test('notes drop the heading, install steps and Markdown', () {
      const body = '## Samgeet 1.4.0\n\n- **Faster search.** Finds more.\n- Bug fixes\n\n### Install\nDownload it.\n\nSHA-256: `abc`';
      final u = AppUpdate.fromRelease(release('v1.4.0', body: body), current: '1.3.2')!;
      expect(u.notes, '• Faster search. Finds more.\n• Bug fixes');
    });
  });
}
