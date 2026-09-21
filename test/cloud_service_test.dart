import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:samgeet/data/cloud_service.dart';
import 'package:samgeet/data/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const asha = Profile(name: 'Asha', email: 'a@b.co', languages: ['bengali'], artists: ['Kishore Kumar'], avatar: 'emoji:🎧', createdAt: 7);

  Future<(CloudService, List<http.Request>)> make({int status = 200, bool offline = false}) async {
    SharedPreferences.setMockInitialValues({});
    final sent = <http.Request>[];
    final client = MockClient((r) async {
      sent.add(r);
      if (offline) throw http.ClientException('offline');
      return http.Response('{}', status);
    });
    return (CloudService(await SharedPreferences.getInstance(), client: client, base: 'https://x.test/api'), sent);
  }

  test('saving sends the profile with a 64-hex install key', () async {
    final (cloud, sent) = await make();
    await cloud.saveProfile(asha);
    expect(sent, hasLength(1));
    expect(sent.single.url.toString(), 'https://x.test/api/profile.php');
    expect(sent.single.headers['X-Install-Key'], matches(RegExp(r'^[a-f0-9]{64}$')));
    final body = jsonDecode(sent.single.body) as Map;
    expect(body['action'], 'save');
    expect(body['email'], 'a@b.co');
    expect(body['avatar'], 'emoji:🎧');
  });

  test('the install key stays the same between requests', () async {
    final (cloud, sent) = await make();
    await cloud.saveProfile(asha);
    await cloud.deleteProfile();
    expect(sent[0].headers['X-Install-Key'], sent[1].headers['X-Install-Key']);
  });

  test('an uploaded photo path is never sent', () async {
    final (cloud, _) = await make();
    final p = asha.copyWith(avatar: '${Profile.photoPrefix}/data/user/avatar.jpg');
    expect(cloud.payload(p)['avatar'], '');
  });

  test('device details are only sent when the listener opted in', () async {
    final (cloud, _) = await make();
    expect(cloud.payload(asha)['device'], isNull);
    expect(cloud.payload(asha)['share_device_info'], false);
  });

  test('a failed save is retried on the next start', () async {
    final (cloud, sent) = await make(offline: true);
    await cloud.saveProfile(asha);
    expect(sent, hasLength(1));
    await cloud.retryPending(asha);
    expect(sent, hasLength(2)); // tried again
  });

  test('a successful save leaves nothing to retry', () async {
    final (cloud, sent) = await make();
    await cloud.saveProfile(asha);
    await cloud.retryPending(asha);
    expect(sent, hasLength(1));
  });

  test('a failed delete is retried even with no profile', () async {
    final (cloud, sent) = await make(offline: true);
    await cloud.deleteProfile();
    await cloud.retryPending(null);
    expect(sent, hasLength(2));
    expect(jsonDecode(sent.last.body)['action'], 'delete');
  });
}
