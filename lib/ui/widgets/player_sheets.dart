import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/saavn_api.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../theme.dart';
import 'common.dart';

Widget _grabber() => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
    );

// ---------------- Queue ----------------
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => ChangeNotifierProvider<PlayerController>.value(
      value: context.read<PlayerController>(),
      child: const _QueueSheet(),
    ),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerController>();
    final current = p.current;
    final upcoming = p.upNext;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.78,
      child: Column(children: [
        _grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Row(children: [
            const Expanded(child: Text('Queue', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22))),
            if (p.loadingMore)
              const Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pink)),
                SizedBox(width: 8),
                Text('Finding more…', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
          ]),
        ),
        if (current != null)
          ListTile(
            leading: Artwork(current.image, size: 48, radius: 10, cacheSize: 150),
            title: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.pink)),
            subtitle: Text(current.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
            trailing: EqualizerBars(animate: p.isPlaying),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('UP NEXT · ${upcoming.length}', style: const TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: upcoming.isEmpty
              ? const Center(child: Text('Nothing queued — smart radio will pick more.', style: TextStyle(color: AppColors.muted)))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: upcoming.length,
                  onReorderItem: (from, to) => p.moveInQueue(p.index + 1 + from, p.index + 1 + to),
                  itemBuilder: (_, i) {
                    final t = upcoming[i];
                    return Dismissible(
                      key: ValueKey('q-${t.id}-${p.index + 1 + i}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.redAccent.withValues(alpha: 0.3),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline_rounded),
                      ),
                      onDismissed: (_) => p.removeFromQueue(p.index + 1 + i),
                      child: ListTile(
                        onTap: () => p.jumpTo(p.index + 1 + i),
                        leading: Artwork(t.image, size: 46, radius: 10, cacheSize: 150),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(t.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded, color: AppColors.muted)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ---------------- Lyrics ----------------
Future<void> showLyricsSheet(BuildContext context, Track track) {
  final api = context.read<SaavnApi>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        _grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(children: [
            Artwork(track.image, size: 44, radius: 10, cacheSize: 120),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text(track.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: AsyncView<String?>(
            load: () => api.lyrics(track.id),
            builder: (_, lyrics) => lyrics == null
                ? const EmptyState(icon: Icons.lyrics_outlined, title: 'No lyrics for this song', message: 'Not every song has lyrics yet.')
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                    children: [Text(lyrics, style: const TextStyle(fontSize: 19, height: 1.7, fontWeight: FontWeight.w600))],
                  ),
          ),
        ),
      ]),
    ),
  );
}

// ---------------- Sleep timer ----------------
Future<void> showSleepSheet(BuildContext context) {
  final p = context.read<PlayerController>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _grabber(),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Sleep timer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
        ),
        if (p.hasSleepTimer)
          ListTile(
            leading: const Icon(Icons.timer_off_rounded, color: AppColors.pink),
            title: Text(p.sleepAtEndOfTrack ? 'Stopping after this song' : 'Cancel timer', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.pink)),
            subtitle: p.sleepEndsAt == null ? null : _SleepCountdown(endsAt: p.sleepEndsAt!),
            onTap: () {
              p.cancelSleepTimer();
              Navigator.of(sheet).pop();
            },
          ),
        for (final m in const [5, 10, 15, 30, 45, 60])
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: Text('$m minutes', style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () {
              p.setSleepTimer(Duration(minutes: m));
              Navigator.of(sheet).pop();
            },
          ),
        ListTile(
          leading: const Icon(Icons.music_note_rounded),
          title: const Text('End of this song', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () {
            p.setSleepAtEndOfTrack();
            Navigator.of(sheet).pop();
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

class _SleepCountdown extends StatefulWidget {
  final DateTime endsAt;
  const _SleepCountdown({required this.endsAt});

  @override
  State<_SleepCountdown> createState() => _SleepCountdownState();
}

class _SleepCountdownState extends State<_SleepCountdown> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now());
    final s = left.isNegative ? 0 : left.inSeconds;
    return Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')} left', style: const TextStyle(color: AppColors.muted));
  }
}

// ---------------- Speed ----------------
Future<void> showSpeedSheet(BuildContext context) {
  final p = context.read<PlayerController>();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _grabber(),
          const SizedBox(height: 14),
          const Align(alignment: Alignment.centerLeft, child: Text('Playback speed', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in const [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0])
              ChoiceChip(
                label: Text('${s}x'),
                selected: p.speed == s,
                onSelected: (_) {
                  p.setSpeed(s);
                  Navigator.of(sheet).pop();
                },
              ),
          ]),
        ]),
      ),
    ),
  );
}
