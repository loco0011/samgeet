import 'package:flutter/material.dart';

import '../../data/catalog.dart';
import '../mood_theme.dart';
import 'glass.dart';

/// Moods a listener can say they like (Settings › Your choices).
const kMoodChoices = <String, String>{
  'romantic': 'Romantic',
  'sad': 'Heartbreak',
  'party': 'Party',
  'chill': 'Chill',
  'workout': 'Workout',
  'focus': 'Focus',
  'devotional': 'Devotional',
  'nostalgia': 'Nostalgia',
  'lofi': 'Lo-fi',
  'rain': 'Rainy day',
};

/// A wrap of chips for picking any number of [choices] (key -> label).
class ChoiceChips extends StatelessWidget {
  final Map<String, String> choices;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const ChoiceChips({super.key, required this.choices, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in choices.entries) GlassChip(label: e.value, selected: selected.contains(e.key), onTap: () => onToggle(e.key)),
      ]);
}

/// Favourite singers, one swipeable row per group so the long list stays compact.
class SingerPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const SingerPicker({super.key, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final mood = moodPalette(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final g in Catalog.artistGroups) ...[
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Row(children: [
            Text(g.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (g.names.any(selected.contains)) ...[
              const SizedBox(width: 8),
              Text('${g.names.where(selected.contains).length} picked', style: TextStyle(color: mood.light, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: g.names.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Center(child: GlassChip(dense: true, label: g.names[i], selected: selected.contains(g.names[i]), onTap: () => onToggle(g.names[i]))),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}
