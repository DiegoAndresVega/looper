import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../audio/wav_decoder.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/sound.dart';
import '../common/waveform_view.dart';
import 'family_picker.dart';

/// The sound editor. Trimming, pitch and volume are non-destructive: they are
/// remembered next to the file, never burnt into it, so a sound can always be
/// opened back up to its full length.
///
/// Reverse is the exception, and it says so by being the only slow control in
/// here: it writes a new file backwards. It cannot be a flag like the others
/// because a chop's sixteen pieces share one file, and a flag would have
/// turned all of them around at once.
class SoundSheet extends StatefulWidget {
  const SoundSheet({
    super.key,
    required this.sound,
    required this.peaks,
    required this.onChanged,
    required this.onReverse,
    required this.onPitch,
    required this.onStretch,
    required this.onDetectTempo,
    required this.onPeaks,
    required this.sessionBpm,
    required this.onPreview,
    required this.onDelete,
    required this.onChop,
  });

  final Sound sound;
  final Float32List peaks;
  final ValueChanged<Sound> onChanged;

  /// Writes the sound backwards and hands back what it became, or null when
  /// the audio could not be read. It is the one edit in this sheet that
  /// touches a file, which is why it is the only one that is asynchronous.
  final Future<Sound?> Function(Sound sound) onReverse;

  /// Transposes for real: the pitch moves and the length does not.
  final Future<Sound?> Function(Sound sound, int semitones) onPitch;

  /// Stretches to the session's tempo, given the tempo it is at now.
  final Future<Sound?> Function(Sound sound, double fromBpm) onStretch;

  /// What tempo the sound seems to be at. Read once, when the sheet opens.
  final Future<double?> Function(Sound sound) onDetectTempo;

  /// The shape of a sound, for redrawing after a rendering.
  final Future<Float32List> Function(Sound sound) onPeaks;

  /// The tempo of the session, which is what stretching aims at.
  final int sessionBpm;
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

  /// The drawn shape. It is state rather than the widget's own field because
  /// reversing changes it: the same envelope read the other way round.
  late Float32List _peaks = widget.peaks;

  /// True while a file is being rewritten. It is the only slow edit here.
  bool _busy = false;

  /// How far the real transposition would move it, in semitones. It is armed
  /// and then applied, not applied on every tap: each one rewrites the file.
  int _semitones = 0;

  /// The tempo read out of the sound, or null while it is being read or when
  /// it could not be read at all.
  double? _tempo;
  bool _readingTempo = true;

  @override
  void initState() {
    super.initState();
    _readTempo();
  }

  Future<void> _readTempo() async {
    final tempo = await widget.onDetectTempo(_sound);
    if (!mounted) return;
    setState(() {
      _tempo = tempo;
      _readingTempo = false;
    });
  }
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
              const SizedBox(height: 14),
              _pitchRow(),
              const SizedBox(height: 10),
              _tempoRow(),
              const SizedBox(height: 10),
              _reverseRow(),
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
        peaks: _peaks,
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

  /// Reverse, out loud. It rewrites the file, so it says what state the
  /// sound is in rather than offering a switch that could be read either way:
  /// «AL REVÉS» while the audio is backwards, and pressing it undoes it.
  Widget _reverseRow() {
    final on = _sound.reversed;
    return GestureDetector(
      onTap: _busy ? null : _reverse,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _sound.family.color : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? _sound.family.color : Palette.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_horiz,
              size: 16,
              color: on ? Palette.onAccent : Palette.ink,
            ),
            const SizedBox(width: 8),
            Text(
              _busy
                  ? 'DÁNDOLE LA VUELTA…'
                  : on
                      ? 'AL REVÉS'
                      : 'DEL REVÉS',
              style: Brand.label(
                10,
                weight: 700,
                color: on ? Palette.onAccent : Palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reverse() async {
    setState(() => _busy = true);
    final next = await widget.onReverse(_sound);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (next != null) _sound = next;
      // The shape is the file's, and the file has turned around: the same
      // envelope read the other way is exactly the new one.
      if (next != null) _peaks = reversedSamples(_peaks);
    });
  }

  /// Real transposition, as opposed to the tape kind the Tono slider does.
  /// It is here and not on a knob because it rewrites the file: a knob you
  /// can drag would rewrite it sixty times a second.
  Widget _pitchRow() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('TONO REAL', style: Brand.label(8.5, weight: 700)),
                const SizedBox(height: 3),
                Text(
                  'Mueve el tono sin cambiar el largo',
                  style: Brand.body(10.5, color: Palette.inkFaint),
                ),
              ],
            ),
          ),
          _round(Icons.remove, _semitones > -12,
              () => setState(() => _semitones--)),
          SizedBox(
            width: 34,
            child: Text(
              _semitones > 0 ? '+$_semitones' : '$_semitones',
              textAlign: TextAlign.center,
              style: Brand.readout(13, weight: 700),
            ),
          ),
          _round(Icons.add, _semitones < 12,
              () => setState(() => _semitones++)),
          const SizedBox(width: 8),
          _applyButton(
            enabled: _semitones != 0,
            onTap: () => _render(() => widget.onPitch(_sound, _semitones)),
          ),
        ],
      ),
    );
  }

  /// The other half of the same coin: the length moves and the pitch does
  /// not, so an imported loop can be made to fit the session's tempo.
  Widget _tempoRow() {
    final tempo = _tempo;
    final label = _readingTempo
        ? 'Leyendo el tempo…'
        : tempo == null
            ? 'No se le encuentra un tempo claro'
            : 'Va a ${tempo.round()} · la sesión, a ${widget.sessionBpm}';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ESTIRAR', style: Brand.label(8.5, weight: 700)),
                const SizedBox(height: 3),
                Text(label, style: Brand.body(10.5, color: Palette.inkFaint)),
              ],
            ),
          ),
          _applyButton(
            enabled: tempo != null &&
                (tempo - widget.sessionBpm).abs() > 0.5,
            onTap: () => _render(() => widget.onStretch(_sound, tempo!)),
          ),
        ],
      ),
    );
  }

  Widget _applyButton({required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled && !_busy ? onTap : null,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: enabled && !_busy ? Palette.accent : Colors.transparent,
          border: Border.all(
            color: enabled && !_busy ? Palette.accent : Palette.line,
          ),
        ),
        child: Text(
          'APLICAR',
          style: Brand.label(
            8.5,
            weight: 700,
            color: enabled && !_busy ? Palette.onAccent : Palette.inkFaint,
          ),
        ),
      ),
    );
  }

  Widget _round(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Palette.line),
        ),
        child: Icon(
          icon,
          size: 15,
          color: enabled ? Palette.ink : Palette.inkFaint,
        ),
      ),
    );
  }

  /// Every rendering follows the same three steps: say it is working, swap
  /// the sound for what came back, and read the new shape and tempo.
  Future<void> _render(Future<Sound?> Function() run) async {
    setState(() => _busy = true);
    final next = await run();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (next != null) {
        _sound = next;
        _semitones = 0;
        _readingTempo = true;
      }
    });
    if (next != null) {
      _peaksFor(next);
      _readTempo();
    }
  }

  /// The drawn shape comes from the file, and the file is a different one now.
  Future<void> _peaksFor(Sound sound) async {
    final peaks = await widget.onPeaks(sound);
    if (!mounted) return;
    setState(() => _peaks = peaks);
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
