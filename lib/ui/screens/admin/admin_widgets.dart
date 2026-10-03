import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/admin_service.dart';
import '../../mood_theme.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';
import '../../widgets/profile_avatar.dart';

// Shared pieces for the admin screens, so every section looks and behaves the same: the same
// panels, numbers, bars and charts as the web panel, in the app's own style.

const kRanges = {'1': 'Today', '7': '7 days', '30': '30 days', '90': '90 days', 'all': 'All time'};

String fmt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String mins(int m) => m < 120 ? '$m min' : '${(m / 60).toStringAsFixed(1)} h';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String day(DateTime? t) => t == null ? '—' : '${t.day} ${_months[t.month - 1]} ${t.year}';

String ago(DateTime? t) {
  if (t == null) return 'Never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 90) return 'Just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 2) return 'Yesterday';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return day(t);
}

/// A titled glass panel; [trailing] sits on the right of the title (a link or a note).
class AdminPanel extends StatelessWidget {
  final String title;
  final String? note;
  final Widget? trailing;
  final Widget child;
  const AdminPanel({super.key, required this.title, this.note, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) => GlassBox(
    radius: 22,
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: title,
                      style: const TextStyle(fontFamily: kDisplay, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (note != null)
                      TextSpan(
                        text: '  $note',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

/// "See all ›" on a panel.
class PanelLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const PanelLink(this.label, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
        ],
      ),
    ),
  );
}

/// "▲ 12%" against the period before, or nothing when there's nothing to compare with.
class ChangeChip extends StatelessWidget {
  final num now;
  final num? before;
  const ChangeChip(this.now, this.before, {super.key});

  @override
  Widget build(BuildContext context) {
    final b = before;
    if (b == null || (b == 0 && now == 0)) return const SizedBox.shrink();
    final p = b == 0 ? null : (100 * (now - b) / b).round();
    final up = p == null || p > 0;
    final color = p == 0 ? AppColors.muted : (up ? const Color(0xFF3FB27F) : const Color(0xFFE2475B));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(
        p == null ? 'new' : (p == 0 ? '±0%' : '${up ? '▲' : '▼'} ${p.abs()}%'),
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// A headline number with a label, an optional change and a line under it.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Widget? change;
  final VoidCallback? onTap;
  const StatTile({super.key, required this.label, required this.value, this.sub, this.change, this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: GlassBox(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              ?change,
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontFamily: kDisplay, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
            ),
          ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.3),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Tiles two to a row.
class StatGrid extends StatelessWidget {
  final List<Widget> children;
  final int columns;
  const StatGrid({super.key, required this.children, this.columns = 2});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: 10),
                Expanded(child: i + c < children.length ? children[i + c] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      );
      if (i + columns < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// A ranked list where each row has a bar for its share of the top row.
class BarList extends StatelessWidget {
  final List<(String, num)> rows;
  final String unit;
  final void Function(int index)? onTap;
  final String empty;
  const BarList(this.rows, {super.key, this.unit = '', this.onTap, this.empty = 'Nothing yet.'});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text(empty, style: const TextStyle(color: AppColors.muted));
    final accent = moodPalette(context).accent;
    final max = rows.map((r) => r.$2).reduce(math.max).toDouble();
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: max <= 0 ? 0.02 : (rows[i].$2 / max).clamp(0.02, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.17), borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            rows[i].$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${fmt(rows[i].$2)}$unit', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple bar chart: one series, or two stacked ([second]). Shows a few labels under the bars.
class MiniBars extends StatelessWidget {
  final List<num> values;
  final List<num>? second;
  final List<String> labels;
  final double height;
  final Color? color;
  final Color? secondColor;
  const MiniBars({super.key, required this.values, this.second, this.labels = const [], this.height = 140, this.color, this.secondColor});

  @override
  Widget build(BuildContext context) {
    final c1 = color ?? moodPalette(context).accent;
    final c2 = secondColor ?? const Color(0xFF5B6B9A);
    final total = [for (var i = 0; i < values.length; i++) values[i] + (second != null && i < second!.length ? second![i] : 0)];
    final max = total.isEmpty ? 0 : total.reduce(math.max);
    final every = labels.length <= 8 ? 1 : (labels.length / 6).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(fmt(max), style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: CustomPaint(painter: _BarsPainter(values, second, c1, c2, max.toDouble())),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Text(
                    i % every == 0 ? labels[i] : '',
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: const TextStyle(color: AppColors.muted, fontSize: 9.5),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<num> a;
  final List<num>? b;
  final Color c1, c2;
  final double max;
  _BarsPainter(this.a, this.b, this.c1, this.c2, this.max);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final y = size.height * g / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (a.isEmpty || max <= 0) return;
    final slot = size.width / a.length;
    final w = math.max(2.0, math.min(22.0, slot * 0.66));
    for (var i = 0; i < a.length; i++) {
      final x = slot * i + (slot - w) / 2;
      final h1 = size.height * a[i] / max;
      final h2 = b != null && i < b!.length ? size.height * b![i] / max : 0.0;
      if (h1 > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, size.height - h1, w, h1),
            topLeft: Radius.circular(h2 > 0 ? 0 : 3),
            topRight: Radius.circular(h2 > 0 ? 0 : 3),
          ),
          Paint()..color = c1,
        );
      }
      if (h2 > 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h1 - h2, w, h2), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
          Paint()..color = c2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.a != a || old.b != b || old.max != max;
}

/// A listener's picture from report data (their emoji or icon, or initials).
class PersonAvatar extends StatelessWidget {
  final J p;
  final double size;
  const PersonAvatar(this.p, {super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => ProfileAvatar(initials: p.s('initials'), avatar: p.s('avatar'), size: size);
}

/// Last seen as a coloured dot and words: green today, amber this week, grey after that.
class SeenDot extends StatelessWidget {
  final DateTime? at;
  const SeenDot(this.at, {super.key});

  @override
  Widget build(BuildContext context) {
    final d = at == null ? null : DateTime.now().difference(at!);
    final color = d == null ? Colors.white24 : (d.inHours < 24 ? const Color(0xFF3FB27F) : (d.inDays < 7 ? const Color(0xFFE0A33F) : Colors.white24));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(ago(at), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color color;
  const Tag(this.text, {super.key, this.color = AppColors.muted});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
    child: Text(
      text,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

const kGreen = Color(0xFF3FB27F);
const kAmber = Color(0xFFE0A33F);
const kRed = Color(0xFFE2475B);
const kViolet = Color(0xFF8F8CF0);

/// Chips to pick a date range.
class RangeChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const RangeChips({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final e in kRanges.entries) ...[
          GlassChip(dense: true, label: e.value, selected: value == e.key, onTap: () => onChanged(e.key)),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

/// Loads a report and shows it as a list that can be pulled to refresh, with loading and error
/// states. Change [reloadKey] to load again (e.g. when a range or filter changes).
class ReportView extends StatefulWidget {
  final Future<J?> Function() load;
  final List<Widget> Function(J data) build;
  final List<Widget> header;
  final Object? reloadKey;
  const ReportView({super.key, required this.load, required this.build, this.header = const [], this.reloadKey});

  @override
  State<ReportView> createState() => ReportViewState();
}

class ReportViewState extends State<ReportView> {
  J? _data;
  bool _loading = true, _failed = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(ReportView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final d = await widget.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = d == null;
      if (d != null) _data = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = <Widget>[];
    if (_data != null) {
      body.addAll(widget.build(_data!));
    } else if (_loading) {
      body.add(
        const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (_failed) {
      body.add(
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(icon: Icons.wifi_off_rounded, title: 'Couldn\'t load this', message: 'Check your connection and pull down to try again.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
        children: [
          ...widget.header,
          if (_loading && _data != null) const LinearProgressIndicator(minHeight: 2),
          for (final w in body) Padding(padding: const EdgeInsets.only(bottom: 12), child: w),
        ],
      ),
    );
  }
}

/// A list row for a listener: picture, name, a second line and something on the right.
class PersonRow extends StatelessWidget {
  final J p;
  final String sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  const PersonRow({super.key, required this.p, required this.sub, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          PersonAvatar(p),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        p.s('name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (p.s('status') == 'blocked') ...[const SizedBox(width: 6), const Tag('blocked', color: kRed)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    ),
  );
}

/// Top songs: cover, title, singer and plays.
class SongList extends StatelessWidget {
  final List<J> songs;
  const SongList(this.songs, {super.key});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const Text('No plays yet.', style: TextStyle(color: AppColors.muted));
    return Column(
      children: [
        for (var i = 0; i < songs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: songs[i].s('image').isNotEmpty
                        ? Artwork(songs[i].s('image'), radius: 0, cacheSize: 120)
                        : const ColoredBox(
                            color: AppColors.surface2,
                            child: Icon(Icons.music_note_rounded, size: 18, color: AppColors.muted),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        songs[i].s('title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        songs[i].s('artist'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(fmt(songs[i].i('plays')), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Label on the left, value on the right; for small fact lists.
class FactRow extends StatelessWidget {
  final String label;
  final String value;
  const FactRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 3,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

List<(String, num)> barRows(List<J> rows, {String label = 'label', String n = 'n'}) => [for (final r in rows) (r.s(label), r.i(n))];

/// Short day labels ("3 Oct") for a list of "YYYY-MM-DD" days.
List<String> dayLabels(List<J> days) => [
  for (final d in days)
    if (DateTime.tryParse(d.s('d')) case final t?) '${t.day} ${_months[t.month - 1]}' else '',
];

const hourLabels = [
  '12a',
  '1a',
  '2a',
  '3a',
  '4a',
  '5a',
  '6a',
  '7a',
  '8a',
  '9a',
  '10a',
  '11a',
  '12p',
  '1p',
  '2p',
  '3p',
  '4p',
  '5p',
  '6p',
  '7p',
  '8p',
  '9p',
  '10p',
  '11p',
];
