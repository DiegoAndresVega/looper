import 'dart:math' as math;

import '../audio/dsp.dart';

/// The knobs of the synthesiser that has always been inside this app.
///
/// `voices.dart` and `dsp.dart` hold a complete little instrument —
/// oscillators, an AD envelope, a biquad, a saturator — and every one of its
/// numbers was nailed down inside the twenty factory sounds. Nobody could
/// touch any of them. This is that engine with handles on it: the same
/// primitives, the same rendering path, and a sound that comes out and lands
/// in the library like any recording.
///
/// Every field is clamped on the way in. A patch arrives from a knob, and a
/// knob is a number somebody can push past what the renderer can survive.
class SynthPatch {
  const SynthPatch({
    this.wave = Wave.sine,
    double pitch = 0.35,
    double bend = 0.5,
    double decay = 0.3,
    double drive = 0,
    double noise = 0,
    double tone = 0.5,
  })  : pitch = pitch < 0 ? 0 : (pitch > 1 ? 1 : pitch),
        bend = bend < 0 ? 0 : (bend > 1 ? 1 : bend),
        decay = decay < 0 ? 0 : (decay > 1 ? 1 : decay),
        drive = drive < 0 ? 0 : (drive > 1 ? 1 : drive),
        noise = noise < 0 ? 0 : (noise > 1 ? 1 : noise),
        tone = tone < 0 ? 0 : (tone > 1 ? 1 : tone);

  /// The oscillator's shape. A sine is a tom, a square is a bleep, and the
  /// saw is where every bass in this kind of music starts.
  final Wave wave;

  /// Knob positions, all 0..1. They are kept as positions rather than as
  /// hertz and seconds so that the knob, the MIDI control and the saved
  /// patch all speak the same language — the mapping to real units lives in
  /// one place, right below.
  final double pitch;
  final double bend;
  final double decay;
  final double drive;
  final double noise;
  final double tone;

  /// Where the note starts, in hertz. Exponential, because pitch is: a knob
  /// that walks 40 Hz to 2 kHz in a straight line spends most of its travel
  /// in the top octave.
  double get startHz => _exp(pitch, 40, 2000);

  /// Where it ends up. The centre of the bend knob is no bend at all; down is
  /// the drop that makes a kick a kick, up is the chirp of a laser.
  double get endHz => startHz * _exp(bend, 0.25, 4);

  /// How long the note lasts, in seconds.
  double get decaySeconds => _exp(decay, 0.03, 2.0);

  /// The colour of the noise layer, in hertz.
  double get toneHz => _exp(tone, 200, 12000);

  bool get hasBend => (bend - 0.5).abs() > 0.01;

  /// The whole sound's length. The tail of the envelope is inaudible long
  /// before it is zero, so the buffer stops at a decay and a half.
  double get seconds => decaySeconds * 1.5;

  SynthPatch copyWith({
    Wave? wave,
    double? pitch,
    double? bend,
    double? decay,
    double? drive,
    double? noise,
    double? tone,
  }) =>
      SynthPatch(
        wave: wave ?? this.wave,
        pitch: pitch ?? this.pitch,
        bend: bend ?? this.bend,
        decay: decay ?? this.decay,
        drive: drive ?? this.drive,
        noise: noise ?? this.noise,
        tone: tone ?? this.tone,
      );

  Map<String, dynamic> toJson() => {
        'wave': wave.name,
        'pitch': pitch,
        'bend': bend,
        'decay': decay,
        'drive': drive,
        'noise': noise,
        'tone': tone,
      };

  factory SynthPatch.fromJson(Map<dynamic, dynamic> json) => SynthPatch(
        wave: Wave.values.asNameMap()[json['wave'] as String?] ?? Wave.sine,
        pitch: (json['pitch'] as num?)?.toDouble() ?? 0.35,
        bend: (json['bend'] as num?)?.toDouble() ?? 0.5,
        decay: (json['decay'] as num?)?.toDouble() ?? 0.3,
        drive: (json['drive'] as num?)?.toDouble() ?? 0,
        noise: (json['noise'] as num?)?.toDouble() ?? 0,
        tone: (json['tone'] as num?)?.toDouble() ?? 0.5,
      );

  /// A knob position turned into a real unit, geometrically. Everything an
  /// ear hears in ratios — pitch, time, frequency — is mapped that way, and a
  /// knob that walks 40 Hz to 2 kHz in a straight line spends most of its
  /// travel inside the top octave.
  static double _exp(double position, double low, double high) =>
      low * math.pow(high / low, position).toDouble();
}
