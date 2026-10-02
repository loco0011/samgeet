import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../player/audio_fx.dart';
import '../../player/player_controller.dart';
import '../mood_theme.dart';
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

// ---------------- Equalizer ----------------
Future<void> showEqualizerSheet(BuildContext context) {
  final fx = context.read<PlayerController>().fx;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => ListenableBuilder(listenable: fx, builder: (context, _) => _EqualizerSheet(fx: fx)),
  );
}

class _EqualizerSheet extends StatelessWidget {
  final AudioFx fx;
  const _EqualizerSheet({required this.fx});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    final unsaved = fx.preset == 'custom';
    final presetLabel = unsaved ? 'Custom · not saved' : fx.presetLabel;
    final presets = fx.allPresets;
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Equalizer', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                const SizedBox(height: 2),
                Text(fx.enabled ? presetLabel : 'Off', style: TextStyle(color: fx.enabled ? mood.light : AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
            if (AudioFx.supported) ...[
              if (unsaved && fx.enabled)
                IconButton(tooltip: 'Save this sound', onPressed: () => _saveAs(context, fx), icon: Icon(Icons.bookmark_add_rounded, color: mood.light)),
              IconButton(tooltip: 'Reset', onPressed: fx.reset, icon: const Icon(Icons.restart_alt_rounded, color: AppColors.muted)),
              Switch(value: fx.enabled, onChanged: fx.setEnabled, activeTrackColor: mood.accent, activeThumbColor: Colors.white),
            ],
          ]),
        ),
        if (!AudioFx.supported)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: EmptyState(icon: Icons.equalizer_rounded, title: 'Equalizer is Android-only', message: 'It uses your phone\'s built-in sound effects.'),
          )
        else ...[
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: presets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                // Last chip: save the current sound under a name.
                if (i == presets.length) {
                  return Pressable(
                    onTap: () => _saveAs(context, fx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: unsaved && fx.enabled ? mood.light : AppColors.outline),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 18, color: mood.light),
                        const SizedBox(width: 4),
                        Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: mood.light)),
                      ]),
                    ),
                  );
                }
                final p = presets[i];
                final on = fx.enabled && fx.preset == p.id;
                return Pressable(
                  onTap: () => fx.applyPreset(p),
                  onLongPress: p.isMine ? () => _presetMenu(context, fx, p) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: on ? mood.gradient : null,
                      color: on ? null : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: on ? Colors.transparent : AppColors.outline),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (p.isMine) ...[
                        Icon(Icons.bookmark_rounded, size: 14, color: on ? Colors.white : mood.light),
                        const SizedBox(width: 5),
                      ],
                      Text(p.label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? Colors.white : Colors.white70)),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (fx.mine.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Long-press one of your sounds to rename, update or delete it', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: fx.bands == null
                ? Container(
                    height: 236,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.outline)),
                    child: const Text('Play a song to tune the bands', style: TextStyle(color: AppColors.muted)),
                  )
                : AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: fx.enabled ? 1 : 0.45, child: _EqGraph(fx: fx, mood: mood)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(children: [
              Icon(Icons.volume_up_rounded, size: 20, color: mood.light),
              const SizedBox(width: 10),
              const Expanded(child: Text('Loudness boost', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(fx.boost == 0 ? 'Off' : '+${fx.boost.toStringAsFixed(1)} dB', style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: mood.accent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: mood.accent.withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Slider(value: fx.boost, max: AudioFx.maxBoost, onChanged: fx.setBoost),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

/// Asks for a name and saves the current sound as one of the listener's presets.
Future<void> _saveAs(BuildContext context, AudioFx fx) async {
  if (fx.bands == null) {
    _eqToast(context, 'Play a song first, then tune and save your sound');
    return;
  }
  if (fx.mine.length >= AudioFx.maxMine) {
    _eqToast(context, 'You can keep ${AudioFx.maxMine} sounds. Delete one to save another.');
    return;
  }
  final name = await _askPresetName(context, fx, title: 'Save this sound', action: 'Save', initial: 'My sound ${fx.mine.length + 1}');
  if (name == null) return;
  final saved = await fx.saveMine(name);
  if (context.mounted && saved != null) _eqToast(context, 'Saved "${saved.label}"');
}

Future<void> _presetMenu(BuildContext context, AudioFx fx, EqPreset p) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _grabber(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
        ),
        ListTile(
          leading: const Icon(Icons.edit_rounded),
          title: const Text('Rename', style: TextStyle(fontWeight: FontWeight.w600)),
          onTap: () async {
            Navigator.of(sheet).pop();
            final name = await _askPresetName(context, fx, title: 'Rename sound', action: 'Rename', initial: p.label, except: p.id);
            if (name != null) await fx.renameMine(p.id, name);
          },
        ),
        ListTile(
          leading: const Icon(Icons.save_as_rounded),
          title: const Text('Update to the current sound', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Keeps the name, saves the bands and boost as they are now', style: TextStyle(color: AppColors.muted)),
          onTap: () async {
            Navigator.of(sheet).pop();
            if (fx.bands == null) return _eqToast(context, 'Play a song first');
            await fx.updateMine(p.id);
            if (context.mounted) _eqToast(context, 'Updated "${p.label}"');
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          title: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent)),
          onTap: () async {
            Navigator.of(sheet).pop();
            await fx.deleteMine(p.id);
            if (context.mounted) _eqToast(context, 'Deleted "${p.label}"');
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// A name for a preset: not empty, not already used, at most [AudioFx.maxNameLength] characters.
Future<String?> _askPresetName(BuildContext context, AudioFx fx, {required String title, required String action, String initial = '', String? except}) {
  final controller = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  String? error;
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        void submit() {
          final name = controller.text.trim();
          if (name.isEmpty) return setState(() => error = 'Give it a name');
          if (!fx.nameFree(name, except: except)) return setState(() => error = 'You already have a sound called that');
          Navigator.of(ctx).pop(name);
        }

        return AlertDialog(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: AudioFx.maxNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: 'e.g. Car bass, Night vocals', errorText: error),
            onChanged: (_) {
              if (error != null) setState(() => error = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.pink), onPressed: submit, child: Text(action)),
          ],
        );
      },
    ),
  );
}

void _eqToast(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
}

/// The bands drawn as one smooth curve; drag anywhere near a band to move it.
class _EqGraph extends StatefulWidget {
  final AudioFx fx;
  final MoodPalette mood;
  const _EqGraph({required this.fx, required this.mood});

  @override
  State<_EqGraph> createState() => _EqGraphState();
}

class _EqGraphState extends State<_EqGraph> {
  static const _height = 190.0, _inset = 18.0;
  int? _active;

  // The phone may allow ±15 dB; the useful range is narrower and easier to aim in.
  double get _lo => math.max(widget.fx.minDb, -12);
  double get _hi => math.min(widget.fx.maxDb, 12);

  void _drag(Offset p, double width, {bool pick = false}) {
    final n = widget.fx.bands!.length;
    if (pick || _active == null) setState(() => _active = (p.dx / width * n).floor().clamp(0, n - 1));
    final t = ((p.dy - _inset) / (_height - 2 * _inset)).clamp(0.0, 1.0);
    final db = _hi - t * (_hi - _lo);
    widget.fx.setBand(_active!, (db * 2).round() / 2); // half-dB steps
  }

  static String _freq(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k' : hz.round().toString();

  @override
  Widget build(BuildContext context) {
    final bands = widget.fx.bands!;
    final gains = [for (final b in bands) b.gain];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(children: [
        Row(children: [
          for (var i = 0; i < gains.length; i++)
            Expanded(
              child: Text(
                '${gains[i] > 0 ? '+' : ''}${gains[i].toStringAsFixed(gains[i] % 1 == 0 ? 0 : 1)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _active == i ? Colors.white : AppColors.muted),
              ),
            ),
        ]),
        LayoutBuilder(
          builder: (_, c) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (d) => _drag(d.localPosition, c.maxWidth, pick: true),
            onPanUpdate: (d) => _drag(d.localPosition, c.maxWidth),
            onPanEnd: (_) => setState(() => _active = null),
            onPanCancel: () => setState(() => _active = null),
            child: CustomPaint(
              size: Size(c.maxWidth, _height),
              painter: _EqCurvePainter(gains: gains, lo: _lo, hi: _hi, inset: _inset, colors: widget.mood.colors, active: _active),
            ),
          ),
        ),
        Row(children: [
          for (final b in bands)
            Expanded(
              child: Text('${_freq(b.centerFrequency)}Hz', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
            ),
        ]),
      ]),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<double> gains;
  final double lo, hi, inset;
  final List<Color> colors;
  final int? active;
  _EqCurvePainter({required this.gains, required this.lo, required this.hi, required this.inset, required this.colors, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final n = gains.length;
    final colW = size.width / n;
    double y(double db) => inset + (hi - db.clamp(lo, hi)) / (hi - lo) * (size.height - 2 * inset);
    final pts = [for (var i = 0; i < n; i++) Offset(colW * (i + 0.5), y(gains[i]))];

    // Guides: a line per band, and the 0 dB line.
    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (final p in pts) {
      canvas.drawLine(Offset(p.dx, inset), Offset(p.dx, size.height - inset), guide);
    }
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), guide..color = Colors.white.withValues(alpha: 0.14));

    // Smooth curve, held flat out to the edges.
    final curve = Path()
      ..moveTo(0, pts.first.dy)
      ..lineTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < n; i++) {
      final a = pts[i - 1], b = pts[i];
      final mx = (a.dx + b.dx) / 2;
      curve.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    curve.lineTo(size.width, pts.last.dy);

    final accent = colors[1];
    final fill = Path.from(curve)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.45), accent.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [for (final c in colors) Color.lerp(c, Colors.white, 0.3)!]).createShader(Offset.zero & size),
    );

    for (var i = 0; i < n; i++) {
      final r = active == i ? 11.0 : 8.0;
      canvas.drawCircle(pts[i], r + 6, Paint()..color = accent.withValues(alpha: active == i ? 0.35 : 0.18));
      canvas.drawCircle(pts[i], r, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], r - 3.5, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) => true;
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
