import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/song.dart';

/// Writing the running order: which pattern, how many bars, in what order.
///
/// The chain — P1 to PN, one bar each — is one bar of thinking. This is the
/// other one, and it is where a loop becomes a piece: intro twice, verse four
/// times, chorus twice, verse again.
///
/// Reordering is two arrows, never a drag. A drag on a phone competes with the
/// sheet's own scroll, and the list is short enough that a swap is one tap.
class SongSheet extends StatefulWidget {
  const SongSheet({
    super.key,
    required this.song,
    required this.songMode,
    required this.currentPattern,
    required this.onChanged,
    required this.onModeChanged,
  });

  final Song song;
  final bool songMode;

  /// The pattern on the grid: what the ADD button adds.
  final int currentPattern;

  final ValueChanged<Song> onChanged;
  final ValueChanged<bool> onModeChanged;

  @override
  State<SongSheet> createState() => _SongSheetState();
}

class _SongSheetState extends State<SongSheet> {
  /// Which entry the arrows and the repeat counter are pointing at. The last
  /// one touched, which is the one you are working on.
  int? _selected;

  Song get _song => widget.song;

  void _emit(Song next, {int? select}) {
    widget.onChanged(next);
    setState(() {
      if (select != null) _selected = select;
      final length = next.steps.length;
      if (length == 0) {
        _selected = null;
      } else if (_selected != null && _selected! >= length) {
        _selected = length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.86,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Palette.ground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            _grabber(),
            const SizedBox(height: 16),
            _header(),
            const SizedBox(height: 16),
            _steps(),
            const SizedBox(height: 14),
            _addButton(),
            if (_selected != null) ...[
              const SizedBox(height: 14),
              _editRow(_selected!),
            ],
            const SizedBox(height: 18),
            _modeSwitch(),
          ],
        ),
      ),
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Palette.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ORDEN DE LOS PATRONES', style: Brand.label(9, weight: 700)),
              const SizedBox(height: 5),
              Text('Canción', style: Brand.title(20)),
            ],
          ),
        ),
        Text(
          '${_song.bars}',
          style: Brand.readout(22, weight: 700, color: Palette.accent),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _song.bars == 1 ? 'COMPÁS' : 'COMPASES',
            style: Brand.label(8, width: 75),
          ),
        ),
      ],
    );
  }

  Widget _steps() {
    if (_song.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          'Sin canción. Añade el patrón que tengas en la rejilla y vuelve a '
          'la rejilla a por el siguiente: la canción se escribe compás a '
          'compás, no de una vez.',
          style: Brand.body(12, color: Palette.inkDim),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < _song.steps.length; i++) _chip(i),
      ],
    );
  }

  /// One entry: the pattern and how many bars it holds. Tapping it points the
  /// controls below at it — nothing else, so a tap can never lose a bar.
  Widget _chip(int index) {
    final step = _song.steps[index];
    final selected = _selected == index;

    return GestureDetector(
      onTap: () => setState(() => _selected = selected ? null : index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Palette.accent : Palette.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Palette.accent : Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'P${step.pattern + 1}',
              style: Brand.readout(
                13,
                weight: 700,
                color: selected ? Palette.onAccent : Palette.ink,
              ),
            ),
            if (step.repeats > 1) ...[
              const SizedBox(width: 5),
              Text(
                '×${step.repeats}',
                style: Brand.label(
                  9,
                  width: 75,
                  weight: 700,
                  color: selected ? Palette.onAccent : Palette.inkDim,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addButton() {
    final full = _song.steps.length >= kSongStepsMax;
    return _wideButton(
      label: full
          ? 'La canción está llena'
          : 'Añadir P${widget.currentPattern + 1}',
      icon: Icons.add,
      enabled: !full,
      onTap: () => _emit(
        _song.appended(SongStep(pattern: widget.currentPattern)),
        select: _song.steps.length,
      ),
    );
  }

  /// What can be done to the entry being pointed at: move it, lengthen it,
  /// or take it out. One row, one action per button.
  Widget _editRow(int index) {
    final step = _song.steps[index];
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'P${step.pattern + 1}',
                style: Brand.readout(14, weight: 700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  step.repeats == 1 ? '1 compás' : '${step.repeats} compases',
                  style: Brand.label(9, width: 75, color: Palette.inkDim),
                ),
              ),
              _round(Icons.remove, step.repeats > 1,
                  () => _emit(_song.withRepeatsAt(index, step.repeats - 1))),
              const SizedBox(width: 6),
              _round(Icons.add, step.repeats < kSongRepeatMax,
                  () => _emit(_song.withRepeatsAt(index, step.repeats + 1))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _round(Icons.chevron_left, index > 0,
                  () => _emit(_song.movedAt(index, -1), select: index - 1)),
              const SizedBox(width: 6),
              _round(Icons.chevron_right, index < _song.steps.length - 1,
                  () => _emit(_song.movedAt(index, 1), select: index + 1)),
              const Spacer(),
              _round(Icons.delete_outline, true,
                  () => _emit(_song.removedAt(index)), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  /// Whether the song is the one deciding what plays next. Off, the chain is
  /// back in charge and the song stays written for later — turning it off is
  /// not erasing it.
  Widget _modeSwitch() {
    final on = widget.songMode;
    final possible = _song.isNotEmpty;

    return _wideButton(
      label: on ? 'La canción manda' : 'Manda la cadena',
      icon: on ? Icons.playlist_play : Icons.repeat_one,
      enabled: possible,
      active: on,
      onTap: () => setState(() => widget.onModeChanged(!on)),
      note: possible
          ? null
          : 'Escribe al menos un paso para que la canción pueda mandar',
    );
  }

  Widget _wideButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool active = false,
    String? note,
  }) {
    final Color ink = !enabled
        ? Palette.inkFaint
        : active
            ? Palette.onAccent
            : Palette.ink;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? Palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: active ? Palette.accent : Palette.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: ink),
                const SizedBox(width: 8),
                Text(label, style: Brand.strong(13, color: ink)),
              ],
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 7),
          Text(note, style: Brand.label(8.5, width: 75, color: Palette.inkFaint)),
        ],
      ],
    );
  }

  Widget _round(IconData icon, bool enabled, VoidCallback onTap,
      {bool danger = false}) {
    final color = !enabled
        ? Palette.inkFaint
        : danger
            ? Palette.rec
            : Palette.ink;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: enabled ? Palette.line : Palette.line),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
