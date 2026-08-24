/// Turning a knob's position into what a parameter actually wants, and back.
///
/// A knob is no longer the only thing that moves these. A learned MIDI control
/// arrives as a position too, and lands on the same parameter through the same
/// maths. Keeping it in one place is what stops «which of these five octaves
/// is 0.6» from having two answers that drift apart the day one of them gains
/// a sixth octave.
library;

import '../core/constants.dart';

/// Above this, a knob standing in for a switch reads as on. A control resting
/// dead centre is off, so nothing comes up armed on its own.
const double kKnobOn = 0.5;

/// How far off centre a pan knob still counts as centred. Centre has to be
/// findable with a thumb, and a pad two per cent off centre is centre.
const double kPanDeadZone = 0.05;

/// Semitones in an octave — the stops on the root knob.
const int kSemitonesPerOctave = 12;

bool knobAsSwitch(double position) => position > kKnobOn;

double switchAsKnob(bool on) => on ? 1 : 0;

/// Which of [length] choices a position picks, and where that choice sits on
/// the dial. One choice pins the knob at the bottom rather than dividing by
/// zero.
int knobAsIndex(double position, int length) {
  if (length <= 1) return 0;
  return (position * (length - 1)).round().clamp(0, length - 1);
}

double indexAsKnob(int index, int length) {
  if (length <= 1) return 0;
  return index.clamp(0, length - 1) / (length - 1);
}

/// The pitch knob: centre is the sound as recorded, an octave either way.
int knobAsSemitones(double position) =>
    (position * kPadPitchRange * 2 - kPadPitchRange)
        .round()
        .clamp(-kPadPitchRange, kPadPitchRange);

double semitonesAsKnob(int semitones) =>
    ((semitones + kPadPitchRange) / (kPadPitchRange * 2)).clamp(0.0, 1.0);

/// Pan, with the dead zone applied on the way in: what comes out is either
/// exactly centre or somewhere it was really meant to be.
double knobAsPan(double position) {
  final pan = (position * 2 - 1).clamp(-1.0, 1.0);
  return pan.abs() < kPanDeadZone ? 0 : pan;
}

double panAsKnob(double pan) => ((pan + 1) / 2).clamp(0.0, 1.0);

/// The root of the scale: twelve stops round the octave.
int knobAsRoot(double position) => knobAsIndex(position, kSemitonesPerOctave);

double rootAsKnob(int root) =>
    indexAsKnob(root % kSemitonesPerOctave, kSemitonesPerOctave);
