import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/loop_length.dart';
import '../../domain/pad_config.dart';
import '../../domain/sound.dart';
import '../library/sound_list.dart';

/// What a long press on a pad opens: which sound it holds, how it behaves and
/// the way out — emptying it. Picking a sound plays it, so the choice is made
/// by ear instead of by name.
class PadSheet extends StatefulWidget {
  const PadSheet({
    super.key,
    required this.title,
    required this.pad,
    required this.sounds,
    required this.onChanged,
    required this.onPreview,
  });

  final String title;
  final PadConfig pad;
  final List<Sound> sounds;
  final ValueChanged<PadConfig> onChanged;
  final ValueChanged<Sound> onPreview;

  @override
  State<PadSheet> createState() => _PadSheetState();
}

class _PadSheetState extends State<PadSheet> {
  late PadConfig _pad = widget.pad;

  void _apply(PadConfig next) {
    setState(() => _pad = next);
    widget.onChanged(next);
  }

  void _pick(Sound sound) {
    widget.onPreview(sound);
    _apply(_pad.copyWith(soundId: sound.id));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Palette.ground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Palette.line),
          left: BorderSide(color: Palette.line),
          right: BorderSide(color: Palette.line),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _header(),
            const SizedBox(height: 16),
            _behaviour(),
            const SizedBox(height: 6),
            Expanded(
              child: SoundList(
                sounds: widget.sounds,
                selectedId: _pad.soundId,
                onPick: _pick,
                padding: const EdgeInsets.only(bottom: 8),
                emptyMessage:
                    'La biblioteca está vacía. Graba algo con el micrófono.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Expanded(
          child: Text(widget.title, style: Brand.title(16)),
        ),
        if (!_pad.isEmpty)
          GestureDetector(
            onTap: () => _apply(_pad.copyWith(clearSound: true)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                'VACIAR PAD',
                style: Brand.label(8.5, weight: 700, color: Palette.rec),
              ),
            ),
          ),
      ],
    );
  }

  Widget _behaviour() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _segmented(
          label: 'Loop',
          options: const ['Libre', 'Al tempo'],
          selected: _pad.synced ? 1 : 0,
          onSelect: (i) => _apply(_pad.copyWith(synced: i == 1)),
        ),
        if (_pad.synced) ...[
          const SizedBox(height: 8),
          _lengths(),
        ],
      ],
    );
  }

  /// Loop length in beats. The pad's current length is always among the
  /// options, even when it came from the factory kit with an odd value.
  Widget _lengths() {
    final choices = loopLengthChoices(_pad.loopSteps);
    return _segmented(
      label: 'Tiempos',
      options: choices.map(loopLengthLabel).toList(),
      selected: choices.indexOf(_pad.loopSteps),
      onSelect: (i) => _apply(_pad.copyWith(loopSteps: choices[i])),
    );
  }

  Widget _segmented({
    required String label,
    required List<String> options,
    required int selected,
    required ValueChanged<int> onSelect,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 74,
          child: Text(
            label.toUpperCase(),
            style: Brand.label(8.5, width: 75, weight: 700),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                Expanded(child: _option(options[i], i == selected, () => onSelect(i))),
                if (i != options.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _option(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Palette.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? Palette.ink : Palette.line),
        ),
        child: Text(
          label,
          style: Brand.strong(
            11.5,
            color: selected ? Palette.ground : Palette.inkDim,
          ),
        ),
      ),
    );
  }
}
