import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../audio/chopper.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/sound.dart';
import '../common/waveform_view.dart';

/// Cutting a sound into pieces that land on the grid in order.
///
/// The sheet is a preview, not an edit: the cuts are drawn over the waveform
/// and nothing is created until CORTAR is pressed. Chopping copies no audio —
/// every piece points at the same file with its own trim — so the only real
/// cost is the pads it takes up, which is why the count is stated up front.
class ChopSheet extends StatefulWidget {
  const ChopSheet({
    super.key,
    required this.sound,
    required this.peaks,
    required this.slicesFor,
  });

  final Sound sound;
  final Float32List peaks;

  /// Where the cuts would fall for a mode. Transients have to read the audio,
  /// so this is asynchronous.
  final Future<List<Slice>> Function(ChopMode mode) slicesFor;

  @override
  State<ChopSheet> createState() => _ChopSheetState();
}

class _ChopSheetState extends State<ChopSheet> {
  ChopMode _mode = ChopMode.transients;
  List<Slice> _slices = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _recalculate();
  }

  Future<void> _recalculate() async {
    setState(() => _busy = true);
    final slices = await widget.slicesFor(_mode);
    if (!mounted) return;
    setState(() {
      _slices = slices;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
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
            _waveform(),
            const SizedBox(height: 16),
            _modes(),
            const SizedBox(height: 20),
            _confirm(),
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
              Text('CORTAR', style: Brand.label(9, weight: 700)),
              const SizedBox(height: 5),
              Text(widget.sound.name, style: Brand.title(20)),
            ],
          ),
        ),
        Text(
          _busy ? '···' : '${_slices.length}',
          style: Brand.readout(22, weight: 700, color: widget.sound.family.color),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _slices.length == 1 ? 'TROZO' : 'TROZOS',
            style: Brand.label(8, width: 75),
          ),
        ),
      ],
    );
  }

  Widget _waveform() {
    final sound = widget.sound;
    final window = sound.trimmedDurationMs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.line),
      ),
      child: Stack(
        children: [
          WaveformView(
            peaks: widget.peaks,
            color: sound.family.color,
            trimStart: sound.trimStartMs / sound.durationMs,
            trimEnd: sound.effectiveEndMs / sound.durationMs,
          ),
          // The cut lines sit over the trimmed window, not the whole file:
          // what is drawn dark is not being chopped.
          Positioned.fill(
            child: LayoutBuilder(builder: (context, box) {
              final left = box.maxWidth * sound.trimStartMs / sound.durationMs;
              final width = box.maxWidth * window / sound.durationMs;
              return Stack(
                children: [
                  for (final slice in _slices.skip(1))
                    Positioned(
                      left: left + width * slice.startMs / window,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 1, color: Palette.ink),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _modes() {
    return Row(
      children: [
        for (final mode in ChopMode.values) ...[
          if (mode != ChopMode.values.first) const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: _busy || mode == _mode
                  ? null
                  : () {
                      setState(() => _mode = mode);
                      _recalculate();
                    },
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mode == _mode ? Palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: mode == _mode ? Palette.accent : Palette.line,
                  ),
                ),
                child: Text(
                  mode.label.toUpperCase(),
                  style: Brand.label(
                    8,
                    width: 75,
                    weight: 700,
                    color: mode == _mode ? Palette.onAccent : Palette.inkDim,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _confirm() {
    final ready = !_busy && _slices.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: ready ? () => Navigator.of(context).pop(_slices) : null,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ready ? widget.sound.family.color : Palette.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ready ? widget.sound.family.color : Palette.line,
              ),
            ),
            child: Text(
              ready ? 'CORTAR EN ${_slices.length}' : 'NADA QUE CORTAR',
              style: Brand.label(
                10,
                weight: 700,
                color: ready ? Palette.onAccent : Palette.inkFaint,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Los trozos van a pads seguidos y comparten el fichero: '
          'cortar no ocupa sitio en el móvil.',
          style: Brand.body(11.5, color: Palette.inkFaint),
        ),
      ],
    );
  }
}
