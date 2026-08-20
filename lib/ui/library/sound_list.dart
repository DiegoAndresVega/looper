import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/sound.dart';

/// One row of the list, or the heading that opens a group. Building the rows
/// as a flat list keeps the scroll cheap however big the library gets.
sealed class _Entry {
  const _Entry();
}

class _Heading extends _Entry {
  const _Heading(this.label, this.count);

  final String label;
  final int count;
}

class _Row extends _Entry {
  const _Row(this.sound);

  final Sound sound;
}

/// The library as a list: the factory kit first, then your recordings, then
/// what you imported. Used both to fill a pad and to manage the library.
class SoundList extends StatelessWidget {
  const SoundList({
    super.key,
    required this.sounds,
    required this.selectedId,
    required this.onPick,
    this.trailing,
    this.padding = EdgeInsets.zero,
    this.emptyMessage = 'Todavía no hay sonidos aquí.',
  });

  final List<Sound> sounds;
  final String? selectedId;
  final ValueChanged<Sound> onPick;

  /// Optional control on the right of each row — preview, delete, edit.
  final Widget Function(Sound sound)? trailing;
  final EdgeInsets padding;
  final String emptyMessage;

  List<_Entry> get _entries {
    final entries = <_Entry>[];
    for (final origin in SoundOrigin.values) {
      final group = sounds.where((s) => s.origin == origin).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (group.isEmpty) continue;
      entries.add(_Heading(origin.label, group.length));
      entries.addAll(group.map(_Row.new));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: Brand.body(12, color: Palette.inkFaint, height: 1.5),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: padding,
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        return switch (entry) {
          _Heading() => _heading(entry),
          _Row() => _row(entry.sound),
        };
      },
    );
  }

  Widget _heading(_Heading heading) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Text(
            heading.label.toUpperCase(),
            style: Brand.label(9, weight: 700),
          ),
          const SizedBox(width: 8),
          Text(
            '${heading.count}',
            style: Brand.readout(9, color: Palette.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _row(Sound sound) {
    final selected = sound.id == selectedId;
    return GestureDetector(
      onTap: () => onPick(sound),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? sound.family.color.withValues(alpha: 0.14)
              : Palette.panel,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? sound.family.color : Palette.line,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: sound.family.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                sound.name,
                overflow: TextOverflow.ellipsis,
                style: Brand.strong(
                  13,
                  color: selected ? Palette.ink : Palette.inkDim,
                ),
              ),
            ),
            Text(
              '${(sound.trimmedDurationMs / 1000).toStringAsFixed(1)} s',
              style: Brand.readout(9.5, color: Palette.inkFaint),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!(sound),
            ],
          ],
        ),
      ),
    );
  }
}
