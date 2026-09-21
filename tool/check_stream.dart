import 'dart:convert';
import 'dart:io';
import 'package:samgeet/data/track.dart';

Future<void> main() async {
  final c = HttpClient();
  final req = await c.getUrl(Uri.parse(
      'https://www.jiosaavn.com/api.php?__call=search.getResults&q=tum+hi+ho&p=1&n=2&_format=json&_marker=0&ctx=web6dot0&api_version=4'));
  final res = await req.close();
  final j = jsonDecode(await res.transform(utf8.decoder).join());
  final t = Track.fromJson(Map<String, dynamic>.from(j['results'][0]));
  print('${t.title} | ${t.artistLine} | ${t.album} | ${t.year} | ${t.language} | 320=${t.has320} | ${t.durationSec}s');
  for (final q in AudioQuality.values) {
    final url = t.streamUrl(q);
    final r = await (await c.getUrl(Uri.parse(url))).close();
    var n = 0;
    await for (final chunk in r) { n += chunk.length; if (n > 200000) break; }
    print('${q.kbps}kbps -> HTTP ${r.statusCode} ${r.headers.contentType} len=${r.headers.contentLength} got>=$n  ${url}');
  }
  print('art: ${t.art(500)}');
  c.close(force: true);
}
