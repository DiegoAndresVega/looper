import 'dart:async';

import '../core/constants.dart';

/// A pad asking to be retriggered on the grid.
typedef StepCallback = void Function(String key);

/// One entry in the clock: something that fires every [steps] sixteenth notes.
class _ClockEntry {
  _ClockEntry(this.key, this.steps, this.startStep);

  final String key;
  final int steps;
  final int startStep;
}

/// Drives every synced loop off a single 16th-note grid so layers land
/// together. Free loops do not go through here — SoLoud loops those natively
/// at their own natural length, which is the default the design asks for.
class TempoClock {
  TempoClock({required this.onStep});

  final StepCallback onStep;

  final Map<String, _ClockEntry> _entries = {};
  Timer? _timer;
  Stopwatch? _watch;

  int _bpm = kDefaultBpm;
  int _stepIndex = 0;
  double _nextStepMs = 0;

  int get bpm => _bpm;
  bool get isRunning => _timer != null;
  bool get hasEntries => _entries.isNotEmpty;

  /// Milliseconds per 16th note at the current tempo.
  double get stepMs => 60000 / _bpm / kStepsPerBeat;

  /// Position inside the current bar, 0..1. Drives the progress rings.
  double progressFor(String key) {
    final entry = _entries[key];
    if (entry == null || _watch == null) return 0;
    final elapsedSteps = _watch!.elapsedMilliseconds / stepMs;
    final since = elapsedSteps - entry.startStep;
    if (since < 0) return 0;
    return (since % entry.steps) / entry.steps;
  }

  /// Changing tempo mid-flight keeps every loop's phase: only the step length
  /// changes, so nothing is cut off.
  void setBpm(int value) {
    _bpm = value.clamp(kBpmMin, kBpmMax);
  }

  void add(String key, int steps) {
    if (_entries.containsKey(key)) return;
    _entries[key] = _ClockEntry(key, steps, _stepIndex);
    if (!isRunning) _start();
  }

  void remove(String key) {
    _entries.remove(key);
    if (_entries.isEmpty) stop();
  }

  bool contains(String key) => _entries.containsKey(key);

  void clear() {
    _entries.clear();
    stop();
  }

  void _start() {
    _stepIndex = 0;
    _nextStepMs = 0;
    _watch = Stopwatch()..start();
    _timer = Timer.periodic(kSchedulerTick, (_) => _scan());
    _scan();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _watch?.stop();
    _watch = null;
  }

  /// Fires each step as it actually arrives. The tick is short enough that
  /// jitter stays under ~8 ms, below what a player notices. Tightening this
  /// further means moving to SoLoud's `playClocked`, which schedules on the
  /// engine's own sample clock — worth doing if the groove ever feels loose.
  void _scan() {
    final watch = _watch;
    if (watch == null) return;
    final now = watch.elapsedMilliseconds;

    while (_nextStepMs <= now) {
      for (final entry in _entries.values) {
        final since = _stepIndex - entry.startStep;
        if (since >= 0 && since % entry.steps == 0) {
          onStep(entry.key);
        }
      }
      _nextStepMs += stepMs;
      _stepIndex++;
    }
  }

  void dispose() => stop();
}
