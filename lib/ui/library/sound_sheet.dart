import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/sound.dart';
import '../common/waveform_view.dart';
import 'family_picker.dart';

/// The sound editor. Everything here is non-destructive: trimming, pitch and
/// volume are remembered next to the file, never burnt into it, so a sound can
/// always be opened back up to its full length.
class SoundSheet extends StatefulWidget {
  const SoundSheet({
    super.key,
    required this.sound,
    required this.peaks,
    required this.onChanged,
    required this.onPreview,
    required this.onDelete,
    required this.onChop,
  });

  final Sound sound;
  final Float32List peaks;
  final ValueChanged<Sound> onChanged;
  final ValueChanged<Sound> onPreview;
  final VoidCallback onDelete;

  /// Cut this sound into pieces across the grid. Closes the sheet first: the
  /// pads it lands on are behind it.
  final VoidCallback onChop;

  @override
  State<SoundSheet> createState() => _SoundSheetState();
}

class _SoundSheetState extends State<SoundSheet> {
  late Sound _sound = widget.sound;
  late final TextEditingController _name =
      TextEditingController(text: widget.sound.name);

  /// The factory kit rebuilds itself on the next launch, so deleting one of
  /// its sounds would only look like it worked.
  bool get _canDelete => _sound.origin != SoundOrigin.factory_;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _apply(Sound next) {
    setState(() => _sound = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: Palette.ground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
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
              const SizedBox(height: 16),
              _waveform(),
              const SizedBox(height: 14),
              _trimRow(),
              const SizedBox(height: 18),
              _nameField(),
              const SizedBox(height: 14),
              FamilyPicker(
                selected: _sound.family,
                onChanged: (family) => _apply(_sound.copyWith(family: family)),
              ),
              const SizedBox(height: 18),
              _slider(
                label: 'Volumen',
                display: '${(_sound.volume * 100).round()}',
                value: _sound.volume,
                onChanged: (v) => _apply(_sound.copyWith(volume: v)),
              ),
              _slider(
                label: 'Tono',
                display: _sound.semitones > 0
                    ? '+${_sound.semitones}'
                    : '${_sound.semitones}',
                value: (_sound.semitones + 12) / 24,
                onChanged: (v) =>
                    _apply(_sound.copyWith(semitones: (v * 24 - 12).round())),
              ),
              const SizedBox(height: 16),
              _actions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _waveform() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.line),
      ),
      child: WaveformView(
        peaks: widget.peaks,
        color: _sound.family.color,
        trimStart: _sound.trimStartMs / _sound.durationMs,
        trimEnd: _sound.effectiveEndMs / _sound.durationMs,
      ),
    );
  }

  Widget _trimRow() {
    final duration = _sound.durationMs.toDouble();
    final start = _sound.trimStartMs.toDouble().clamp(0.0, duration);
    final end = _sound.effectiveEndMs.toDouble().clamp(start + 1, duration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('RECORTE', style: Brand.label(9, weight: 700)),
            Text(
              '${(_sound.trimmedDurationMs / 1000).toStringAsFixed(2)} s',
              style: Brand.readout(10.5, color: Palette.inkDim),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _sound.family.color,
            inactiveTrackColor: Palette.line,
            thumbColor: Palette.ink,
            overlayColor: _sound.family.color.withValues(alpha: 0.14),
            trackHeight: 3,
          ),
          child: RangeSlider(
            min: 0,
            max: duration,
            values: RangeValues(start, end),
            onChanged: (range) => _apply(
              _sound.copyWith(
                trimStartMs: range.start.round(),
                trimEndMs: range.end.round(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _name,
      maxLength: 18,
      style: Brand.strong(15),
      cursorColor: Palette.accent,
      onChanged: (value) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return;
        _apply(_sound.copyWith(name: trimmed));
      },
      decoration: InputDecoration(
        counterText: '',
        labelText: 'Nombre',
        labelStyle: Brand.label(9, weight: 700),
        filled: true,
        fillColor: Palette.panel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Palette.accent),
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required String display,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 66,
          child: Text(
            label.toUpperCase(),
            style: Brand.label(9, width: 75, weight: 700),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _sound.family.color,
              inactiveTrackColor: Palette.line,
              thumbColor: Palette.ink,
              overlayColor: _sound.family.color.withValues(alpha: 0.14),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: Brand.readout(10.5, color: Palette.inkDim),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => widget.onPreview(_sound),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _sound.family.color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'ESCUCHAR',
                style: Brand.label(10, weight: 700, color: Palette.onAccent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: widget.onChop,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                'CORTAR',
                style: Brand.label(10, weight: 700, color: Palette.ink),
              ),
            ),
          ),
        ),
        if (_canDelete) ...[
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: _confirmDelete,
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Palette.rec),
                ),
                child: Text(
                  'BORRAR',
                  style: Brand.label(10, weight: 700, color: Palette.rec),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.panel,
        title: Text('Borrar ${_sound.name}', style: Brand.title(16)),
        content: Text(
          'Se borra el archivo y se vacían los pads que lo usaban. No hay vuelta atrás.',
          style: Brand.body(12.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCELAR',
                style: Brand.label(9, weight: 700, color: Palette.inkDim)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('BORRAR',
                style: Brand.label(9, weight: 700, color: Palette.rec)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
    widget.onDelete();
  }
}
