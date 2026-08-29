import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dart:math' as math;

import '../core/constants.dart';
import '../domain/pattern.dart';
import '../domain/song.dart';

/// One step leaving the sequencer, with everything the engine needs to place
/// it: the notes, how hard, how far off the grid, and into how many hits.
///
/// Offsets are fractions of a step rather than milliseconds so the sequencer
/// stays ignorant of tempo — converting to time is the engine's business.
class StepPlay {
  const StepPlay({
    required this.notes,
    this.velocity = kVelocityMax,
    this.offsetSteps = 0,
    this.ratchet = 1,
  });

  final Set<String> notes;
  final double velocity;

  /// How long after its tick this fires, in steps. An early note carries the
  /// offset from the *previous* tick, so it is always non-negative here.
  final double offsetSteps;

  /// How many evenly spaced hits this step packs.
  final int ratchet;
}

/// The step sequencer, the way a groovebox does it: sixteen steps, sixteen
/// patterns, and two ways of writing into them.
///
/// **Live (REC):** every pad you hit lands on the current step and the write
/// head moves on by itself. Pads hit close together stack on the same step, so
/// a chord stays a chord. The rest button moves on leaving silence behind.
///
/// **Directed (a step is selected):** the step stays put and each pad toggles
/// its note in it. Nothing advances until you say so.
///
/// It knows nothing about audio: it hands a set of notes to [onNotes] and lets
/// the caller make the noise. That is what makes it testable without a device.
class Sequencer extends ChangeNotifier {
  Sequencer({
    required this.onNotes,
    required this.onPatternsChanged,
    this.chordWindow = kChordWindow,
    double Function()? random,
  }) : _random = random ?? math.Random().nextDouble;

  /// Fires one step's worth of playing. An empty set is a rest, and must stay
  /// silent rather than repeating whatever sounded last.
  final void Function(StepPlay play) onNotes;

  /// The dice for probability, injectable so tests can load them. Only rolled
  /// for steps whose probability is below one: an untouched pattern never
  /// consults chance at all.
  final double Function() _random;

  /// The patterns changed and the session should be written to disk.
  final VoidCallback onPatternsChanged;

  /// How long notes keep landing on the same step while recording live.
  final Duration chordWindow;

  List<Pattern> _patterns =
      List.generate(kPatternCount, (_) => Pattern.empty());
  int _index = 0;
  int _chainLength = 1;

  /// The order the patterns play in when the chain is not enough, and whether
  /// it is switched on. An empty song never takes the wheel: switching the
  /// mode on before writing anything would silently stop the chain.
  Song _song = const Song.empty();
  bool _songMode = false;

  /// Which bar of the song is sounding. It counts up for ever and the song
  /// wraps it, so a song does not have to know how long it has been running.
  int _bar = 0;
  bool _on = false;
  bool _playing = false;
  bool _recording = false;

  /// Steps left of the courtesy bar before writing actually begins, or null
  /// when nothing is being counted. A groovebox gives you a bar to get your
  /// hand ready; this app used to start writing under the finger.
  int? _countIn;

  /// Where the head is. Starts at -1 on play so the first tick lands on 0.
  int _step = 0;

  /// Steps since PLAY, counting up and never wrapping. With tracks of
  /// different lengths there is no point where everything starts over — that
  /// is what polymeter *is* — so the sequencer keeps an absolute count and
  /// lets each track take its own remainder of it.
  int _globalStep = 0;
  int? _editingStep;
  Timer? _chordTimer;

  /// A step already sent out early by the previous tick — (pattern, step) —
  /// so its own tick knows not to sound it again.
  (int, int)? _firedEarly;

  bool get isOn => _on;
  bool get isPlaying => _playing;
  bool get isRecording => _recording;

  /// True during the courtesy bar: armed, audible, not yet writing.
  bool get isCountingIn => _countIn != null;

  /// Which beat of the count-in is going by, 1..4. Something to read while
  /// waiting, so the bar does not feel like the app hung.
  int get countInBeat {
    final left = _countIn;
    if (left == null) return 1;
    final gone = kStepsPerBar - left;
    return gone ~/ kStepsPerBeat + 1;
  }
  int get currentStep => _step < 0 ? 0 : _step;
  int? get editingStep => _editingStep;
  int get patternIndex => _index;
  Pattern get pattern => _patterns[_index];
  List<Pattern> get patterns => List.unmodifiable(_patterns);

  /// True while the grid is being used to write, not to play: the pads need
  /// to know so they can show what they are doing.
  bool get isWriting => _recording || _editingStep != null;

  /// How many patterns play back to back — the groovebox way of going past
  /// one bar. 1 loops the pattern on screen; 8 walks P1 to P8, eight bars.
  int get chainLength => _chainLength;

  set chainLength(int value) {
    _chainLength = value.clamp(1, kPatternCount);
    if (_playing && _index >= _chainLength) {
      _index = 0;
    }
    notifyListeners();
  }

  /// The song, and whether it is the one deciding what plays next.
  Song get song => _song;
  bool get songMode => _songMode;

  /// True only when the song is both switched on and worth following.
  bool get isFollowingSong => _songMode && _song.isNotEmpty;

  /// Which bar of the song is playing, counted from the moment PLAY was hit.
  int get songBar => _bar;

  /// Which entry of the song is sounding, so the strip can light it.
  int? get songIndex => isFollowingSong ? _song.indexForBar(_bar) : null;

  void setSong(Song value) {
    _song = value;
    if (_playing && isFollowingSong) {
      _index = _song.patternForBar(_bar);
    }
    onPatternsChanged();
    notifyListeners();
  }

  set songMode(bool value) {
    if (_songMode == value) return;
    _songMode = value;
    if (_playing && isFollowingSong) {
      _bar = 0;
      _index = _song.patternForBar(0);
    }
    onPatternsChanged();
    notifyListeners();
  }

  // ------------------------------------------------------------------ state

  /// Replaces every pattern, as when a session opens.
  void load(
    List<Pattern> patterns,
    int index, {
    int chainLength = 1,
    Song song = const Song.empty(),
    bool songMode = false,
  }) {
    _patterns = [
      for (var i = 0; i < kPatternCount; i++)
        i < patterns.length ? patterns[i] : Pattern.empty(),
    ];
    _index = _isValidPattern(index) ? index : 0;
    _chainLength = chainLength.clamp(1, kPatternCount);
    _song = song;
    _songMode = songMode;
    _bar = 0;
    _step = 0;
    _editingStep = null;
    notifyListeners();
  }

  void toggleOn() {
    _on = !_on;
    if (!_on) {
      _stopEverything();
    }
    notifyListeners();
  }

  void togglePlay() {
    _cancelChord();
    _countIn = null;
    _firedEarly = null;
    if (_playing) {
      _playing = false;
      _step = 0;
      _bar = 0;
      _globalStep = 0;
    } else {
      _playing = true;
      _recording = false;
      _editingStep = null;
      _bar = 0;
      _globalStep = -1;
      // A chain, and a song, always tell their story from the first bar.
      if (isFollowingSong) {
        _index = _song.patternForBar(0);
      } else if (_chainLength > 1) {
        _index = 0;
      }
      // The first tick moves to zero, so step one is heard, not skipped.
      _step = -1;
    }
    notifyListeners();
  }

  /// Arms writing. The first press starts a bar of count-in rather than
  /// writing straight away; pressing again during that bar calls it off.
  void toggleRecord() {
    _cancelChord();
    if (_recording || _countIn != null) {
      _recording = false;
      _countIn = null;
      notifyListeners();
      return;
    }
    _playing = false;
    _editingStep = null;
    _step = 0;
    _countIn = kStepsPerBar;
    notifyListeners();
  }

  /// Picks the step to write into by hand. Passing the step already selected,
  /// or null, leaves directed editing.
  void selectStep(int? step) {
    _cancelChord();
    if (step == null || step == _editingStep) {
      _editingStep = null;
    } else if (step >= 0 && step < kPatternSteps) {
      _editingStep = step;
      _recording = false;
    }
    notifyListeners();
  }

  void selectPattern(int index) {
    if (!_isValidPattern(index)) return;
    _cancelChord();
    _index = index;
    notifyListeners();
  }

  // ----------------------------------------------------------------- writing

  /// A pad was hit. What happens depends on how the sequencer is being used;
  /// when it is not writing, nothing happens here and the pad just sounds.
  void tap(String note) {
    final editing = _editingStep;
    if (editing != null) {
      _write(pattern.toggled(editing, note));
      return;
    }
    if (!_recording) return;

    _write(pattern.withNote(_step, note));
    _chordTimer ??= Timer(chordWindow, () {
      _chordTimer = null;
      _advance();
      notifyListeners();
    });
  }

  /// Leaves the current step as it is and moves on: this is how a rest gets
  /// written.
  void rest() {
    if (!_recording) return;
    _cancelChord();
    _advance();
    notifyListeners();
  }

  void clearStep(int step) => _write(pattern.clearedStep(step));

  /// Sets how hard the step being edited hits. Only meaningful while a step is
  /// selected by hand — the accent belongs to a step you are pointing at, not
  /// to wherever the write head happens to be.
  void setStepVelocity(double velocity) {
    final step = _editingStep;
    if (step == null) return;
    _write(pattern.withVelocity(step, velocity));
  }

  /// How hard the step being edited hits, or full when none is selected.
  double get editingVelocity =>
      _editingStep == null ? kVelocityMax : pattern.velocityAt(_editingStep!);

  double get editingProbability =>
      _editingStep == null ? 1.0 : pattern.probabilityAt(_editingStep!);

  double get editingNudge =>
      _editingStep == null ? 0.0 : pattern.nudgeAt(_editingStep!);

  int get editingRatchet =>
      _editingStep == null ? 1 : pattern.ratchetAt(_editingStep!);

  void setStepProbability(double value) {
    final step = _editingStep;
    if (step != null) _write(pattern.withProbability(step, value));
  }

  void setStepNudge(double value) {
    final step = _editingStep;
    if (step != null) _write(pattern.withNudge(step, value));
  }

  void setStepRatchet(int value) {
    final step = _editingStep;
    if (step != null) _write(pattern.withRatchet(step, value));
  }

  /// How long the track of [note] runs inside the pattern on screen, and how
  /// to change it. A whole bar unless somebody says otherwise.
  int trackLength(String note) => pattern.lengthFor(note);

  void setTrackLength(String note, int steps) =>
      _write(pattern.withLength(note, steps));

  /// Which pads the pattern on screen uses, in pad order.
  List<String> get tracks => pattern.tracks.toList()..sort();

  /// Swaps the whole pattern on screen — how a copied pattern is pasted.
  void replacePattern(Pattern next) => _write(next);

  void clearPattern() => _write(pattern.cleared());

  void _write(Pattern next) {
    _patterns = List<Pattern>.of(_patterns)..[_index] = next;
    onPatternsChanged();
    notifyListeners();
  }

  // --------------------------------------------------------------- playback

  /// One 16th note went by. Called from the tempo clock so the pattern rides
  /// the same grid as the synced loops.
  void tick() {
    final counting = _countIn;
    if (counting != null) {
      final left = counting - 1;
      if (left <= 0) {
        // The bar is up: the head sits on step one, ready for the first hit.
        _countIn = null;
        _recording = true;
        _step = 0;
      } else {
        _countIn = left;
      }
      notifyListeners();
      return;
    }
    if (!_playing) return;
    final wrapped = _step == kPatternSteps - 1;
    if (wrapped) {
      // End of the bar: whoever owns the running order hands over to the next
      // pattern, and the grid follows so the lights always show what sounds.
      // The song wins when it is on, because it is the more specific answer
      // to the same question the chain answers.
      if (isFollowingSong) {
        _bar++;
        _index = _song.patternForBar(_bar);
      } else if (_chainLength > 1) {
        _index = (_index + 1) % _chainLength;
      }
    }
    _advance();
    _globalStep++;

    // This step — unless the previous tick already sent it out early.
    final firedEarly = _firedEarly == (_index, _step);
    _firedEarly = null;
    if (!firedEarly) {
      // A late step keeps its lag; an early one whose preview never happened
      // (playback just started here) sounds on time rather than never.
      final nudge = pattern.nudgeAt(_step);
      _emit(pattern, _step, _globalStep, offsetSteps: nudge > 0 ? nudge : 0);
    }

    // One step of lookahead: a step pushed *early* has to leave on this tick,
    // riding the remainder of it. Crossing the bar line follows the chain,
    // so the first step of the next pattern can lean into this one.
    final (nextPattern, nextStep) = _positionAfter();
    final nextNudge = _patterns[nextPattern].nudgeAt(nextStep);
    if (nextNudge < 0) {
      _emit(
        _patterns[nextPattern],
        nextStep,
        _globalStep + 1,
        offsetSteps: 1 + nextNudge,
      );
      _firedEarly = (nextPattern, nextStep);
    }
    notifyListeners();
  }

  /// Where the head goes on the next tick, chain included.
  (int, int) _positionAfter() {
    final wrapped = _step == kPatternSteps - 1;
    final nextStep = (_step + 1) % kPatternSteps;
    if (!wrapped) return (_index, nextStep);
    if (isFollowingSong) return (_song.patternForBar(_bar + 1), nextStep);
    return (_chainLength > 1 ? (_index + 1) % _chainLength : _index, nextStep);
  }

  /// Sends one step out, rolling the dice only when the step asks for it.
  /// A lost roll goes out as a rest, so the listener still hears every tick.
  ///
  /// [step] is where the bar is and [globalStep] is where the sequence is.
  /// The notes come from the second — each track takes its own remainder of
  /// it — and the layers from the first: an accent, a nudge and a ratchet
  /// belong to a place in the bar, which is what a player is listening to
  /// even when a track underneath is running to its own length.
  void _emit(
    Pattern source,
    int step,
    int globalStep, {
    double offsetSteps = 0,
  }) {
    final notes = source.soundingAt(globalStep);
    final probability = source.probabilityAt(step);
    final silenced =
        notes.isNotEmpty && probability < 1.0 && _random() > probability;
    onNotes(StepPlay(
      notes: silenced ? const {} : notes,
      velocity: source.velocityAt(step),
      offsetSteps: offsetSteps,
      ratchet: source.ratchetAt(step),
    ));
  }

  void _advance() => _step = (_step + 1) % kPatternSteps;

  void _stopEverything() {
    _cancelChord();
    _countIn = null;
    _firedEarly = null;
    _playing = false;
    _recording = false;
    _editingStep = null;
    _step = 0;
    _bar = 0;
    _globalStep = 0;
  }

  void _cancelChord() {
    _chordTimer?.cancel();
    _chordTimer = null;
  }

  bool _isValidPattern(int index) => index >= 0 && index < kPatternCount;

  @override
  void dispose() {
    _cancelChord();
    super.dispose();
  }
}
