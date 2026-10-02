import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/download_service.dart';
import '../../data/track.dart';
import '../../player/player_controller.dart';
import '../mood_theme.dart';
import '../nav.dart';
import '../theme.dart';
import 'common.dart';
import 'detail_scaffold.dart';
import 'track_widgets.dart';

/// A small mark next to a song: saved on the phone, downloading (with progress) or waiting.
class DownloadBadge extends StatelessWidget {
  final String trackId;
  const DownloadBadge({super.key, required this.trackId});

  @override
  Widget build(BuildContext context) {
    final (state, progress) = context.select<DownloadService, (DownloadState, double?)>((d) => (d.stateOf(trackId), d.progressOf(trackId)));
    final mood = moodPalette(context);
    final Widget? mark = switch (state) {
      DownloadState.done => Icon(Icons.download_done_rounded, size: 15, color: mood.light),
      DownloadState.downloading => SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, value: progress == 0 ? null : progress, color: mood.light, backgroundColor: Colors.white12),
        ),
      DownloadState.queued => const Icon(Icons.schedule_rounded, size: 14, color: AppColors.muted),
      _ => null,
    };
    if (mark == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(right: 5), child: mark);
  }
}

/// "Download all" for an album or playlist: shows how far along it is, and
/// turns into a tick once every song is saved.
class DownloadAllButton extends StatelessWidget {
  final List<Track> tracks;
  const DownloadAllButton({super.key, required this.tracks});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<DownloadService>();
    final saved = tracks.where((t) => dl.isDownloaded(t.id)).length;
    final going = tracks.where((t) {
      final s = dl.stateOf(t.id);
      return s == DownloadState.downloading || s == DownloadState.queued;
    }).length;
    final mood = moodPalette(context);

    if (tracks.isNotEmpty && saved == tracks.length) {
      return RoundIconButton(
        icon: Icons.download_done_rounded,
        color: mood.light,
        tooltip: 'Downloaded',
        onTap: () => toast(context, 'All ${plural(saved, 'song')} are saved on this phone'),
      );
    }
    if (going > 0) {
      return RoundIconButton(
        icon: Icons.downloading_rounded,
        color: mood.light,
        tooltip: 'Downloading',
        onTap: () => toast(context, 'Saving $saved of ${tracks.length}… Watch it in Library › Downloads'),
      );
    }
    return RoundIconButton(
      icon: Icons.download_rounded,
      tooltip: 'Download',
      onTap: () async {
        if (!await requireSignIn(context, reason: 'Sign in to download songs and listen without internet.')) return;
        final n = dl.downloadAll(tracks);
        if (context.mounted) toast(context, n == 0 ? 'Already downloaded' : 'Downloading ${plural(n, 'song')} for offline listening');
      },
    );
  }
}

/// Everything saved for offline listening, plus what is still downloading.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = context.watch<DownloadService>();
    final songs = dl.songs;
    final player = context.read<PlayerController>();
    if (songs.isEmpty && !dl.busy) {
      return const EmptyState(
        icon: Icons.download_for_offline_outlined,
        title: 'No downloads yet',
        message: 'Tap ⋮ on a song and choose Download, or the download button on an album or playlist. '
            'Downloaded songs play without internet, in the same quality.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 30),
      itemCount: songs.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (songs.isNotEmpty)
                PlayBar(
                  onPlay: () => player.playTracks(songs, context: 'downloads'),
                  onShuffle: () => player.playTracks(songs, shuffleOn: true, context: 'downloads'),
                  extra: [
                    RoundIconButton(icon: Icons.delete_sweep_outlined, tooltip: 'Remove all', onTap: () => confirmRemoveAllDownloads(context)),
                  ],
                ),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.sd_storage_outlined, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${plural(songs.length, 'song')} · ${DownloadService.size(dl.totalBytes)} on this phone · ${dl.quality.detail}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                  ),
                ),
              ]),
              if (dl.busy)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: moodPalette(context).light)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Downloading ${plural(dl.pending, 'song')}…', style: const TextStyle(fontWeight: FontWeight.w600))),
                    TextButton(onPressed: dl.cancelAll, child: const Text('Cancel')),
                  ]),
                ),
            ]),
          );
        }
        final t = songs[i - 1];
        return Dismissible(
          key: ValueKey('dl-${t.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.redAccent.withValues(alpha: 0.3),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline_rounded),
          ),
          onDismissed: (_) {
            dl.remove(t.id);
            toast(context, 'Removed "${t.title}" from downloads');
          },
          child: TrackTile(track: t, showLike: true, onTap: () => player.playTracks(songs, start: i - 1, context: 'downloads')),
        );
      },
    );
  }
}

Future<void> confirmRemoveAllDownloads(BuildContext context) async {
  final dl = context.read<DownloadService>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remove all downloads?'),
      content: Text('This frees ${DownloadService.size(dl.totalBytes)} on your phone. The songs stay in your library and still stream online.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
      ],
    ),
  );
  if (ok == true) await dl.removeAll();
}
