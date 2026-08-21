import 'dart:async';

import '../core/constants.dart';

/// A pad asking to be retriggered on the grid.
typedef StepCallback = void Function(String key);

/// Milliseconds since the grid started. Real playback reads a stopwatch; the
/// tests hand in their own so the grid can be checked without waiting.
typedef ElapsedReader = int Function();

/// Opens a fresh time source. Called every time the grid starts from zero.
typedef ElapsedReaderFactory = ElapsedReader Function();

ElapsedReader _stopwatchReader() {
  final watch = Stopwatch()..start();
  return () => watch.elapsedMilliseconds;
}

/// Milliseconds of one 16th note at [bpm]. The single definition of the grid:
/// the clock, the roll and anything else that repeats in time read it here so
/// they can never disagree about where a step falls.
double stepMsAt(int bpm) => 60000 / bpm / kStepsPerBeat;

/// How often the roll retriggers, in [steps] sixteenth notes per hit.
///
/// Kept in microseconds because a 16th at 220 BPM is 68 ms: rounding to whole
/// milliseconds would drag the fill behind the grid it is played over.
Duration rollIntervalFor({required int bpm, required int steps}) =>
    Duration(microseconds: (stepMsAt(bpm) * steps * 1000).round());

/// How a roll division reads on a button: the note value it repeats at.
/// The instrument is 4/4 throughout, so a bar is a whole note and the
/// denominator is simply how many of these fit in one.
String rollDivisionLabel(int steps) => '1/${kStepsPerBar ~/ steps}';

/// One entry in the clock: something that fires every [steps] sixteenth notes,
/// counting from [startStep] of the shared grid.
class _ClockEntry {
  const _ClockEntry(this.key, this.steps, this.startStep);

  final String key;
  final int steps;
  final int startStep;
}

/// Drives every synced loop off a single 16th-note grid so layers land
/// together. Free loops do not go through here — SoLoud repeats those natively
/// at their own natural length, which is what a pad set to «Libre» asks for.
///
/// The grid has one downbeat and everything hangs off it. Whatever starts the
/// clock defines that downbeat and sounds immediately; anything added later
/// waits for its next boundary instead of starting under the finger. That wait
/// is the whole point: it is what makes the second loop land on top of the
/// first instead of a fifth of a beat behind it.
class TempoClock {
  TempoClock({required this.onStep, ElapsedReaderFactory? timeSource})
      : _openTimeSource = timeSource ?? _stopwatchReader;

  final StepCallback onStep;
  final ElapsedReaderFactory _openTimeSource;

  final Map<String, _ClockEntry> _entries = {};
  Timer? _timer;
  ElapsedReader? _elapsed;

  int _bpm = kDefaultBpm;
  int _stepIndex = 0;
  double _nextStepMs = 0;

  int get bpm => _bpm;
  bool get isRunning => _timer != null;
  bool get hasEntries => _entries.isNotEmpty;

  /// Milliseconds per 16th note at the current tempo.
  double get stepMs => stepMsAt(_bpm);

  /// Where the grid is right now, in fractional 16th notes since the downbeat.
  /// It is read off the step index rather than off raw milliseconds so that
  /// changing the tempo mid-flight does not make the rings jump.
  double get position {
    final elapsed = _elapsed;
    if (elapsed == null) return 0;
    final remaining = (_nextStepMs - elapsed()) / stepMs;
    return _stepIndex - remaining.clamp(0.0, 1.0);
  }

  /// Position inside the current bar, 0..1. Drives the progress rings.
  double progressFor(String key) {
    final entry = _entries[key];
    if (entry == null || _elapsed == null) return 0;
    final since = position - entry.startStep;
    if (since < 0) return 0;
    return (since % entry.steps) / entry.steps;
  }

  /// True while an entry is on the grid but still waiting for its downbeat.
  /// The pad is lit and armed; it has simply not sounded yet.
  bool isPending(String key) {
    final entry = _entries[key];
    if (entry == null) return false;
    return position < entry.startStep;
  }

  /// Changing tempo mid-flight keeps every loop's phase: only the step length
  /// changes, so nothing is cut off.
  void setBpm(int value) {
    _bpm = value.clamp(kBpmMin, kBpmMax);
  }

  /// Puts something on the grid. It fires every [steps] sixteenth notes.
  ///
  /// [alignTo] is the boundary it waits for, its own length by default. The
  /// sequencer uses it to fire every step while still starting on a bar line.
  void add(String key, int steps, {int? alignTo}) {
    if (_entries.containsKey(key)) return;
    if (isRunning) {
      _entries[key] = _ClockEntry(key, steps, _nextBoundary(alignTo ?? steps));
      return;
    }
    // Nothing was running: this one is the downbeat, so it sounds at once.
    _entries[key] = _ClockEntry(key, steps, 0);
    _start();
  }

  /// The next point on the grid a whole number of [steps] from the downbeat.
  /// Lengths are musical divisions, so two entries aligned this way share
  /// their downbeats for as long as both are running.
  int _nextBoundary(int steps) {
    if (steps <= 1) return _stepIndex;
    return ((_stepIndex + steps - 1) ~/ steps) * steps;
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
    _elapsed = _openTimeSource();
    _timer = Timer.periodic(kSchedulerTick, (_) => _scan());
    _scan();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _elapsed = null;
  }

  /// How far behind the grid may fall before it stops trying to catch up step
  /// by step and simply jumps to where the music actually is.
  static const int _maxCatchUpSteps = 4;

  /// Fires each step as it actually arrives. The tick is short enough that
  /// jitter stays under ~8 ms, below what a player notices, and every entry
  /// due on the same step is fired in the same pass — so layers stay locked
  /// to each other even when the pass itself runs a little late.
  void _scan() {
    final elapsed = _elapsed;
    if (elapsed == null) return;
    final now = elapsed();

    // Coming back from the background, time has run on while the timer slept.
    // Skipping to where the grid really is beats firing every step that went
    // by, which comes out as a burst of noise. The jump is a whole number of
    // steps, so nothing loses its place on the grid.
    final behind = (now - _nextStepMs) / stepMs;
    if (behind > _maxCatchUpSteps) {
      final skipped = behind.floor();
      _stepIndex += skipped;
      _nextStepMs += skipped * stepMs;
    }

    while (_nextStepMs <= now) {
      // A snapshot: firing a step can end up adding or dropping entries.
      for (final entry in _entries.values.toList(growable: false)) {
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
