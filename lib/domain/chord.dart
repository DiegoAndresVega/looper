/// How many notes a key of the scale keyboard plays at once.
///
/// The intervals are counted in *degrees of the scale*, never in semitones:
/// stacking thirds over a minor scale gives a minor chord and over a major
/// one gives a major chord, without anybody having to decide which. That is
/// the same trick the locked scale already plays — the key is chosen once and
/// then no wrong note is reachable.
enum ChordVoicing {
  single('Sola', [0]),
  third('Tercera', [0, 2]),
  triad('Tríada', [0, 2, 4]),
  seventh('Séptima', [0, 2, 4, 6]);

  const ChordVoicing(this.label, this.degrees);

  final String label;

  /// Offsets in scale degrees from the key that was pressed.
  final List<int> degrees;

  bool get isChord => degrees.length > 1;
}

/// Whether the notes of a chord arrive together or one after another, and in
/// what order.
enum ArpMode {
  off('Junto'),
  up('Sube'),
  down('Baja'),
  upDown('Sube y baja');

  const ArpMode(this.label);

  final String label;

  bool get isOn => this != ArpMode.off;
}

/// The order the notes leave in. A new list every time: the caller's is very
/// often the step's own set of notes.
List<T> arpSequence<T>(List<T> notes, ArpMode mode) {
  if (notes.length < 2 || !mode.isOn) return List<T>.of(notes);
  return switch (mode) {
    ArpMode.off => List<T>.of(notes),
    ArpMode.up => List<T>.of(notes),
    ArpMode.down => notes.reversed.toList(),
    // Up and back down without playing either end twice: with three notes
    // that is four hits, not six, so the figure keeps landing on the beat.
    ArpMode.upDown => [
        ...notes,
        ...notes.reversed.skip(1).take(notes.length - 2),
      ],
  };
}

/// Where each hit of an [count]-note arpeggio falls inside its step, as a
/// fraction of the step. Even spacing: an arpeggio that does not divide its
/// step evenly stops sounding like a subdivision and starts sounding late.
List<double> arpOffsets(int count) =>
    [for (var i = 0; i < count; i++) i / count];
