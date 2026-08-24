/// The grid as a scale.
///
/// Sixteen pads stop being sixteen sounds and become sixteen degrees of one
/// scale, playing the chosen sound at those pitches. Locking the scale is what
/// lets someone with no ear avoid a wrong note — the README's promise, "making
/// music without knowing production", applied to melody rather than rhythm.
///
/// Everything here is semitones from the root. Who sounds them is the engine's
/// problem, which is what keeps this testable without a device.
library;

/// The scales worth offering on a pocket instrument. Not a hundred tunings:
/// the two anyone recognises, the two that cannot sound wrong, one that makes
/// anything sound like a film, and chromatic for when the scale is in the way.
enum Scale {
  pentatonicMinor('Pentatónica menor', [0, 3, 5, 7, 10]),
  pentatonicMajor('Pentatónica mayor', [0, 2, 4, 7, 9]),
  minor('Menor', [0, 2, 3, 5, 7, 8, 10]),
  major('Mayor', [0, 2, 4, 5, 7, 9, 11]),
  dorian('Dórica', [0, 2, 3, 5, 7, 9, 10]),
  chromatic('Cromática', [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);

  const Scale(this.label, this.steps);

  final String label;

  /// Semitones above the root, one per degree, inside a single octave.
  final List<int> steps;
}

/// Note names, written the way they are read out loud in Spanish.
const List<String> kNoteNames = [
  'Do', 'Do#', 'Re', 'Re#', 'Mi', 'Fa',
  'Fa#', 'Sol', 'Sol#', 'La', 'La#', 'Si',
];

/// How many semitones above the root the pad at [pad] plays.
///
/// Past the end of the scale it carries on into the next octave rather than
/// stopping, so a five-degree pentatonic spreads over three octaves across the
/// grid — which is why a pentatonic here reads as a solo and not as a drill.
int semitonesForPad(
  int pad, {
  required Scale scale,
  required int root,
  required int octave,
}) {
  if (pad < 0) return 0;
  final degrees = scale.steps.length;
  final octaveOffset = pad ~/ degrees;
  return root + (octave + octaveOffset) * 12 + scale.steps[pad % degrees];
}

/// How far the keyboard can be shifted, in octaves. Two either way covers the
/// range a sampled sound survives being played at, and the list is the knob's
/// stops as well as the clamp.
const List<int> kScaleOctaves = [-2, -1, 0, 1, 2];

/// The name of a pitch, ignoring which octave it lands in.
String noteName(int semitones) => kNoteNames[semitones % 12];

/// Prime marks by octave, the way a score writes them.
const List<String> _octaveMarks = ['', '′', '″', '‴'];

/// What to print on the pad: the note, plus a prime mark per octave above the
/// first. Short enough to survive a pad a centimetre wide.
String padLabel(int semitones, {required int root}) {
  final octave = ((semitones - root) ~/ 12).clamp(0, _octaveMarks.length - 1);
  return '${noteName(semitones)}${_octaveMarks[octave]}';
}
