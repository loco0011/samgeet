import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/share_service.dart';
import 'package:samgeet/data/track.dart';

void main() {
  const t1 = Track(
    id: 'abc',
    title: 'Tum Hi Ho & more',
    artists: [ArtistRef(id: '1', name: 'Arijit Singh')],
    album: 'Aashiqui 2',
    image: 'https://c.saavncdn.com/430/x-150x150.jpg',
  );
  const t2 = Track(id: 'def', title: 'Second');

  test('a song link carries title, artist, album and 500px art', () {
    final u = Uri.parse(ShareService.songLink(t1));
    expect(u.host, 'api.sambitmaity.fun');
    expect(u.path, '/share.php');
    expect(u.queryParameters['t'], 'song');
    expect(u.queryParameters['s'], 'Tum Hi Ho & more');
    expect(u.queryParameters['a'], 'Arijit Singh');
    expect(u.queryParameters['al'], 'Aashiqui 2');
    expect(u.queryParameters['i'], 'https://c.saavncdn.com/430/x-500x500.jpg');
  });

  test('a song with no artist or album leaves those out', () {
    final u = Uri.parse(ShareService.songLink(t2));
    expect(u.queryParameters.containsKey('a'), isFalse);
    expect(u.queryParameters.containsKey('al'), isFalse);
    expect(u.queryParameters.containsKey('i'), isFalse);
  });

  test('a playlist link imports straight back, even pasted inside a longer message', () {
    final link = ShareService.playlistLink('Road trip', [t1, t2]);
    final u = Uri.parse(link);
    expect(u.queryParameters['n'], 'Road trip');
    expect(u.queryParameters['c'], '2');
    final d = ShareService.decodePlaylist('🎧 "Road trip" on Samgeet\n\n1. Tum Hi Ho\n\nGet Samgeet:\n$link')!;
    expect(d.name, 'Road trip');
    expect(d.ids, ['abc', 'def']);
  });
}
