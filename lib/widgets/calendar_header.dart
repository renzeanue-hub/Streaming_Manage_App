import 'package:flutter/material.dart';
import '../models/stream_category.dart';
import '../models/streamer.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.streamers,
    required this.selectedStreamerIds,
    required this.selectedCategoryNames,
    required this.onStreamerFilterChanged,
    required this.onCategoryFilterChanged,
  });

  final List<Streamer> streamers;
  final Set<String> selectedStreamerIds;
  final Set<String> selectedCategoryNames;

  final ValueChanged<Set<String>> onStreamerFilterChanged;
  final ValueChanged<Set<String>> onCategoryFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        chipTheme: Theme.of(context).chipTheme.copyWith(
          labelStyle: const TextStyle(fontSize: 12),
        ),
      ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterGroup(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in streamers)
                  FilterChip(
                    label: Text(s.name),
                    selected: selectedStreamerIds.contains(s.id),
                    avatar: CircleAvatar(backgroundColor: s.color, radius: 8),
                    onSelected: (v) {
                      final next = {...selectedStreamerIds};
                      if (v) {
                        next.add(s.id);
                      } else {
                        next.remove(s.id);
                      }
                      onStreamerFilterChanged(next);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _FilterGroup(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in StreamCategory.values)
                  FilterChip(
                    label: Text(c.label),
                    selected: selectedCategoryNames.contains(c.name),
                    onSelected: (v) {
                      final next = {...selectedCategoryNames};
                      if (v) {
                        next.add(c.name);
                      } else {
                        next.remove(c.name);
                      }
                      onCategoryFilterChanged(next);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    )
    );
  }
}


class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    this.title,
    required this.child,
  });

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
          ],
          child,
        ],
      ),
    );
  }
}
