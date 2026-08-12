import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../domain/pattern.dart';

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
  });

  /// Fires every note of a step. An empty set is a rest, and must stay silent
  /// rather than repeating whatever sounded last.
  final void Function(Set<String> notes) onNotes;

  /// The patterns changed and the session should be written to disk.
  final VoidCallback onPatternsChanged;

  /// How long notes keep landing on the same step while recording live.
  final Duration chordWindow;

  List<Pattern> _patterns =
      List.generate(kPatternCount, (_) => Pattern.empty());
  int _index = 0;
  bool _on = false;
  bool _playing = false;
  bool _recording = false;

  /// Where the head is. Starts at -1 on play so the first tick lands on 0.
  int _step = 0;
  int? _editingStep;
  Timer? _chordTimer;

  bool get isOn => _on;
  bool get isPlaying => _playing;
  bool get isRecording => _recording;
  int get currentStep => _step < 0 ? 0 : _step;
  int? get editingStep => _editingStep;
  int get patternIndex => _index;
  Pattern get pattern => _patterns[_index];
  List<Pattern> get patterns => List.unmodifiable(_patterns);

  /// True while the grid is being used to write, not to play: the pads need
  /// to know so they can show what they are doing.
  bool get isWriting => _recording || _editingStep != null;

  // ------------------------------------------------------------------ state

  /// Replaces every pattern, as when a session opens.
  void load(List<Pattern> patterns, int index) {
    _patterns = [
      for (var i = 0; i < kPatternCount; i++)
        i < patterns.length ? patterns[i] : Pattern.empty(),
    ];
    _index = _isValidPattern(index) ? index : 0;
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
    if (_playing) {
      _playing = false;
      _step = 0;
    } else {
      _playing = true;
      _recording = false;
      _editingStep = null;
      // The first tick moves to zero, so step one is heard, not skipped.
      _step = -1;
    }
    notifyListeners();
  }

  void toggleRecord() {
    _cancelChord();
    _recording = !_recording;
    if (_recording) {
      _playing = false;
      _editingStep = null;
      _step = 0;
    }
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
    if (!_playing) return;
    _advance();
    onNotes(pattern.at(_step));
    notifyListeners();
  }

  void _advance() => _step = (_step + 1) % kPatternSteps;

  void _stopEverything() {
    _cancelChord();
    _playing = false;
    _recording = false;
    _editingStep = null;
    _step = 0;
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
