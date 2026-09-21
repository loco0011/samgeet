import 'package:flutter_test/flutter_test.dart';
import 'package:samgeet/data/deep_link.dart';
import 'package:samgeet/data/share_service.dart';
import 'package:samgeet/data/track.dart';

void main() {
  const song = Track(id: 'Xy_9-a', title: 'Tum Hi Ho', artists: [ArtistRef(id: '1', name: 'Arijit Singh')]);
  const other = Track(id: 'b2', title: 'Two');

  test('a shared song link opens as that song', () {
    final l = parseSharedLink(ShareService.songLink(song));
    expect(l, isA<SharedSong>());
    expect((l as SharedSong).id, 'Xy_9-a');
    expect(l.title, 'Tum Hi Ho');
  });

  test('the samgeet://share form (page button) works for songs and playlists', () {
    final s = parseSharedLink('samgeet://share?t=song&id=abc123&s=Hello');
    expect((s as SharedSong).id, 'abc123');

    final web = ShareService.playlistLink('Road trip', [song, other]);
    final asApp = web.replaceFirst('https://api.sambitmaity.fun/share.php', 'samgeet://share');
    final p = parseSharedLink(asApp) as SharedPlaylist;
    expect(p.name, 'Road trip');
    expect(p.ids, ['Xy_9-a', 'b2']);
  });

  test('a shared playlist link opens as that playlist', () {
    final p = parseSharedLink(ShareService.playlistLink('Road trip', [song, other])) as SharedPlaylist;
    expect(p.name, 'Road trip');
    expect(p.ids, ['Xy_9-a', 'b2']);
  });

  test('links that are not ours, or are malformed, are ignored', () {
    expect(parseSharedLink('https://evil.example/share.php?t=song&id=abc'), isNull);
    expect(parseSharedLink('https://api.sambitmaity.fun/other.php?t=song&id=abc'), isNull);
    expect(parseSharedLink('http://api.sambitmaity.fun/share.php?t=song&id=abc'), isNull);
    expect(parseSharedLink('samgeet://other?t=song&id=abc'), isNull);
    expect(parseSharedLink('https://api.sambitmaity.fun/share.php?t=song'), isNull);
    expect(parseSharedLink('https://api.sambitmaity.fun/share.php?t=song&id=../../x'), isNull);
    expect(parseSharedLink('https://api.sambitmaity.fun/share.php?t=playlist&n=x'), isNull);
    expect(parseSharedLink(''), isNull);
  });
}
