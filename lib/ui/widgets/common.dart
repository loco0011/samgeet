import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../mood_theme.dart';
import '../theme.dart';

/// Rounded network artwork with a soft loading shimmer and a graceful fallback.
class Artwork extends StatelessWidget {
  final String url;
  final double? size;
  final double radius;
  final bool circle;
  final int cacheSize;

  const Artwork(this.url, {super.key, this.size, this.radius = 14, this.circle = false, this.cacheSize = 400});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: const BoxDecoration(gradient: AppColors.gradient),
      alignment: Alignment.center,
      child: Icon(circle ? Icons.person_rounded : Icons.music_note_rounded, color: Colors.white70, size: (size ?? 56) * 0.42),
    );
    final Widget img = url.isEmpty
        ? placeholder
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: cacheSize,
            fadeInDuration: const Duration(milliseconds: 250),
            placeholder: (_, _) => const SkeletonBox(),
            errorWidget: (_, _, _) => placeholder,
          );
    final clipped = circle
        ? ClipOval(child: img)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
    return SizedBox(width: size, height: size, child: clipped);
  }
}

/// Animated loading placeholder.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height, this.radius = 0});

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + 3 * _c.value, 0),
            end: Alignment(-0.5 + 3 * _c.value, 0),
            colors: [Colors.white.withValues(alpha: 0.04), Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.04)],
          ),
        ),
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Gradient? gradient;
  const GradientText(this.text, {super.key, this.style, this.gradient});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => (gradient ?? AppColors.gradient).createShader(r),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style?.copyWith(fontFamily: kDisplay) ?? const TextStyle(fontFamily: kDisplay)),
    );
  }
}

/// For [AnimatedSwitcher]: draw only the incoming child, never the outgoing one
/// underneath it (the default stacks both, so the old view ghosts through).
Widget currentOnlyLayout(Widget? current, List<Widget> previous) => current ?? const SizedBox.shrink();

/// Squishes slightly when pressed — makes every tap feel alive.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.96});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool compact;
  const GradientButton({super.key, required this.label, this.icon, this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22, vertical: compact ? 10 : 14),
        decoration: BoxDecoration(
          gradient: mood.gradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 3.5,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [mood.colors[0], mood.colors[2]]),
                  boxShadow: [BoxShadow(color: mood.accent.withValues(alpha: 0.7), blurRadius: 10)],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kDisplay, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              ),
            ]),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(left: 13.5, top: 4),
                child: Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              ),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// Little animated bars shown next to the song that's playing.
class EqualizerBars extends StatefulWidget {
  final bool animate;
  final Color color;
  final double size;
  const EqualizerBars({super.key, this.animate = true, this.color = AppColors.pink, this.size = 18});

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.animate && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (i) {
            final phase = _c.value * 2 * math.pi + i * 1.3;
            final h = widget.animate ? 0.3 + 0.7 * ((math.sin(phase) + 1) / 2) : 0.3 + 0.1 * i;
            return Container(
              width: widget.size / 6,
              height: widget.size * h,
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
            );
          }),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle, border: Border.all(color: AppColors.outline)),
            child: Icon(icon, size: 38, color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, style: const TextStyle(color: AppColors.muted), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// Loads something asynchronously with a skeleton, an error state and retry.
class AsyncView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final Widget? loading;
  const AsyncView({super.key, required this.load, required this.builder, this.loading});

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  void _retry() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Can\'t load right now',
            message: '${snap.error}',
            action: GradientButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: _retry, compact: true),
          );
        }
        if (!snap.hasData) return widget.loading ?? const Center(child: CircularProgressIndicator(color: AppColors.pink));
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          layoutBuilder: currentOnlyLayout,
          child: widget.builder(context, snap.data as T),
        );
      },
    );
  }
}

/// Skeleton rows used while song lists load.
class TrackListSkeleton extends StatelessWidget {
  final int count;
  const TrackListSkeleton({super.key, this.count = 8});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(children: [
            SkeletonBox(width: 54, height: 54, radius: 12),
            SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 180, height: 14, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 12, radius: 6),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
