import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';

/// Tempo control: a big number between minus and plus. A tap moves one unit;
/// holding accelerates in two tiers, so crossing the whole range takes about a
/// second without lifting your thumb. TAP sets it by feel instead.
class TempoStepper extends StatefulWidget {
  const TempoStepper({super.key, required this.bpm, required this.onChanged});

  final int bpm;
  final ValueChanged<int> onChanged;

  @override
  State<TempoStepper> createState() => _TempoStepperState();
}

class _TempoStepperState extends State<TempoStepper> {
  Timer? _holdDelay;
  Timer? _repeat;
  Stopwatch? _held;
  final List<DateTime> _taps = [];

  @override
  void dispose() {
    _holdDelay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  void _bump(int direction) =>
      widget.onChanged((widget.bpm + direction).clamp(kBpmMin, kBpmMax));

  void _startHold(int direction) {
    _bump(direction);
    _held = Stopwatch()..start();
    _holdDelay = Timer(kStepperHoldDelay, () {
      _repeat = Timer.periodic(kStepperRepeatInterval, (_) {
        final fast = (_held?.elapsed ?? Duration.zero) > kStepperFastThreshold;
        _bump(direction * (fast ? kStepperFastAmount : 1));
      });
    });
  }

  void _endHold() {
    _holdDelay?.cancel();
    _repeat?.cancel();
    _held?.stop();
  }

  /// Four taps in rhythm and the tempo follows.
  void _tap() {
    final now = DateTime.now();
    _taps
      ..removeWhere((t) => now.difference(t) > const Duration(milliseconds: 2500))
      ..add(now);
    if (_taps.length >= 2) {
      var total = 0;
      for (var i = 1; i < _taps.length; i++) {
        total += _taps[i].difference(_taps[i - 1]).inMilliseconds;
      }
      final average = total / (_taps.length - 1);
      if (average > 0) {
        widget.onChanged((60000 / average).round().clamp(kBpmMin, kBpmMax));
      }
    }
    if (_taps.length > 4) _taps.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stepButton('−', -1),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.bpm}',
                style: Brand.readout(22, weight: 700),
              ),
              Text(
                'BPM',
                style: Brand.label(8, tracking: 0.3),
              ),
            ],
          ),
        ),
        _stepButton('+', 1),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _tap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Palette.line),
            ),
            child: Text(
              'TAP',
              style: Brand.label(9, weight: 700, color: Palette.inkDim),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepButton(String glyph, int direction) {
    return GestureDetector(
      onTapDown: (_) => _startHold(direction),
      onTapUp: (_) => _endHold(),
      onTapCancel: _endHold,
      child: Container(
        width: 46,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.panelHigh,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          glyph,
          style: Brand.strong(21, height: 1),
        ),
      ),
    );
  }
}
