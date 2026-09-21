import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Rebuilds with the artwork's accent colour once it's been computed.
class DominantColorBuilder extends StatefulWidget {
  final String url;
  final Widget Function(BuildContext context, Color color) builder;
  const DominantColorBuilder({super.key, required this.url, required this.builder});

  @override
  State<DominantColorBuilder> createState() => _DominantColorBuilderState();
}

class _DominantColorBuilderState extends State<DominantColorBuilder> {
  Color _color = DominantColor.fallback;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(DominantColorBuilder old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    final cached = DominantColor.peek(url);
    if (cached != null) {
      _color = cached;
      return;
    }
    DominantColor.of(url).then((c) {
      if (mounted && widget.url == url) setState(() => _color = c);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _color);
}

/// Picks a vibrant accent colour from album artwork, so the player can glow
/// in the colours of whatever is playing. No extra packages needed.
class DominantColor {
  static final Map<String, Color> _cache = {};
  static const Color fallback = Color(0xFF7B2FF7);

  static Color? peek(String url) => _cache[url];

  static Future<Color> of(String url) async {
    if (url.isEmpty) return fallback;
    final hit = _cache[url];
    if (hit != null) return hit;

    final completer = Completer<Color>();
    final provider = ResizeImage(CachedNetworkImageProvider(url), width: 32, height: 32);
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) async {
      stream.removeListener(listener);
      try {
        final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        completer.complete(data == null ? fallback : _pick(data));
      } catch (_) {
        completer.complete(fallback);
      }
    }, onError: (_, _) {
      stream.removeListener(listener);
      if (!completer.isCompleted) completer.complete(fallback);
    });
    stream.addListener(listener);

    final color = await completer.future.timeout(const Duration(seconds: 8), onTimeout: () => fallback);
    if (_cache.length > 80) _cache.remove(_cache.keys.first);
    return _cache[url] = color;
  }

  static Color _pick(ByteData data) {
    double r = 0, g = 0, b = 0, total = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final pr = data.getUint8(i), pg = data.getUint8(i + 1), pb = data.getUint8(i + 2);
      final mx = math.max(pr, math.max(pg, pb)) / 255;
      final mn = math.min(pr, math.min(pg, pb)) / 255;
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      // Favour vivid, reasonably bright pixels; ignore near-black and near-white.
      if (mx < 0.18 || (mx > 0.96 && sat < 0.1)) continue;
      final w = 0.15 + sat * sat * mx * 3;
      r += pr * w;
      g += pg * w;
      b += pb * w;
      total += w;
    }
    if (total == 0) return fallback;
    final hsv = HSVColor.fromColor(Color.fromARGB(255, (r / total).round(), (g / total).round(), (b / total).round()));
    // Keep it dark enough to sit behind white text, but still colourful.
    return hsv.withSaturation(math.max(hsv.saturation, 0.45)).withValue(hsv.value.clamp(0.45, 0.85)).toColor();
  }
}
