import 'package:flutter/material.dart';

import '../../audio/dsp.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/synth_patch.dart';

/// The synthesiser, with its knobs out.
///
/// The engine that renders the factory kit was always in the binary — twenty
/// voices with every number written into them and no way to touch one. This
/// sheet is the same engine with handles: six sliders and a waveform, and
/// what comes out lands in the library like a recording, because from there
/// on it *is* one.
///
/// Everything is auditioned before it is kept. A synth you cannot hear while
/// you turn the knob is a list of numbers.
class SynthSheet extends StatefulWidget {
  const SynthSheet({
    super.key,
    required this.onAudition,
    required this.onCreate,
  });

  /// Renders the patch and plays it, without keeping anything.
  final Future<void> Function(SynthPatch patch) onAudition;

  /// Keeps it: renders, writes the file and puts it in the library.
  final Future<void> Function(SynthPatch patch, String name) onCreate;

  @override
  State<SynthSheet> createState() => _SynthSheetState();
}

class _SynthSheetState extends State<SynthSheet> {
  SynthPatch _patch = const SynthPatch();
  final TextEditingController _name =
      TextEditingController(text: 'Sintetizado');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Every move is heard. Turning a knob on a synth and not hearing it is
  /// the one thing a synth cannot do.
  void _set(SynthPatch next) {
    setState(() => _patch = next);
    widget.onAudition(next);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Palette.ground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          children: [
            _grabber(),
            const SizedBox(height: 16),
            _header(),
            const SizedBox(height: 16),
            _waves(),
            const SizedBox(height: 14),
            _slider(
              label: 'Tono',
              display: '${_patch.startHz.round()} Hz',
              value: _patch.pitch,
              onChanged: (v) => _set(_patch.copyWith(pitch: v)),
            ),
            _slider(
              label: 'Caída',
              display: _patch.hasBend
                  ? '${_patch.endHz.round()} Hz'
                  : 'Recta',
              value: _patch.bend,
              onChanged: (v) => _set(_patch.copyWith(bend: v)),
            ),
            _slider(
              label: 'Largo',
              display: '${(_patch.decaySeconds * 1000).round()} ms',
              value: _patch.decay,
              onChanged: (v) => _set(_patch.copyWith(decay: v)),
            ),
            _slider(
              label: 'Drive',
              display: _patch.drive == 0
                  ? 'Limpio'
                  : '${(_patch.drive * 100).round()}',
              value: _patch.drive,
              onChanged: (v) => _set(_patch.copyWith(drive: v)),
            ),
            _slider(
              label: 'Ruido',
              display: _patch.noise == 0
                  ? 'Nada'
                  : '${(_patch.noise * 100).round()}',
              value: _patch.noise,
              onChanged: (v) => _set(_patch.copyWith(noise: v)),
            ),
            _slider(
              label: 'Color',
              display: '${_patch.toneHz.round()} Hz',
              value: _patch.tone,
              enabled: _patch.noise > 0,
              onChanged: (v) => _set(_patch.copyWith(tone: v)),
            ),
            const SizedBox(height: 14),
            _nameField(),
            const SizedBox(height: 16),
            _actions(),
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

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SINTETIZAR', style: Brand.label(9, weight: 700)),
                const SizedBox(height: 5),
                Text('Un sonido nuevo', style: Brand.title(20)),
              ],
            ),
          ),
        ],
      );

  Widget _waves() {
    const names = {
      Wave.sine: 'Seno',
      Wave.triangle: 'Triángulo',
      Wave.saw: 'Sierra',
      Wave.square: 'Cuadrada',
    };

    return Row(
      children: [
        for (final wave in Wave.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => _set(_patch.copyWith(wave: wave)),
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _patch.wave == wave ? Palette.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _patch.wave == wave ? Palette.ink : Palette.line,
                  ),
                ),
                child: Text(
                  names[wave]!,
                  style: Brand.label(
                    8.5,
                    weight: 700,
                    color: _patch.wave == wave ? Palette.ground : Palette.inkDim,
                  ),
                ),
              ),
            ),
          ),
          if (wave != Wave.values.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _slider({
    required String label,
    required String display,
    required double value,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label.toUpperCase(),
              style: Brand.label(
                8.5,
                width: 75,
                weight: 700,
                color: enabled ? Palette.inkDim : Palette.inkFaint,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: enabled ? Palette.accent : Palette.line,
                inactiveTrackColor: Palette.line,
                thumbColor: enabled ? Palette.accent : Palette.lineLive,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: Brand.readout(
                10,
                color: enabled ? Palette.ink : Palette.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: _name,
      style: Brand.strong(14),
      cursorColor: Palette.accent,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Palette.accent),
        ),
        hintText: 'Nombre',
        hintStyle: Brand.body(13, color: Palette.inkFaint),
      ),
    );
  }

  Widget _actions() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => widget.onAudition(_patch),
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Palette.line),
              ),
              child: Text(
                'ESCUCHAR',
                style: Brand.label(10, weight: 700, color: Palette.ink),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _busy ? null : _create,
            child: Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.accent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _busy ? 'GUARDANDO…' : 'GUARDARLO',
                style: Brand.label(10, weight: 700, color: Palette.onAccent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    setState(() => _busy = true);
    await widget.onCreate(_patch, name.isEmpty ? 'Sintetizado' : name);
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
