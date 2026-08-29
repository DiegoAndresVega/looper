import '../core/constants.dart';

/// One entry of a song: a pattern, and how many bars it holds the floor
/// before the next entry takes over.
///
/// Both numbers are clamped on the way in rather than trusted. A song comes
/// back off disk with whatever the file says, and a pattern index out of
/// range would ask the sequencer for a bar that does not exist.
class SongStep {
  const SongStep({required int pattern, int repeats = 1})
      : pattern = pattern < 0
            ? 0
            : (pattern >= kPatternCount ? kPatternCount - 1 : pattern),
        repeats = repeats < 1
            ? 1
            : (repeats > kSongRepeatMax ? kSongRepeatMax : repeats);

  final int pattern;
  final int repeats;

  SongStep withRepeats(int value) =>
      SongStep(pattern: pattern, repeats: value);

  Map<String, dynamic> toJson() => {'pattern': pattern, 'repeats': repeats};

  factory SongStep.fromJson(Map<dynamic, dynamic> json) => SongStep(
        pattern: (json['pattern'] as num?)?.toInt() ?? 0,
        repeats: (json['repeats'] as num?)?.toInt() ?? 1,
      );
}

/// The order the patterns play in, and for how long each one lasts.
///
/// The chain — P1 to PN, one bar each, always in that order — is the
/// groovebox's cheap answer to going past one bar. This is the other one: any
/// pattern, any number of times, in any order. Intro twice, verse four times,
/// chorus twice, verse again.
///
/// It is a list of bars, not a timeline of seconds: the song asks «which
/// pattern is bar seven?» and never has an opinion about tempo. That is what
/// keeps it playable from the same 16th-note clock as everything else, and
/// testable without a device.
class Song {
  const Song._(this.steps);

  const Song.empty() : steps = const [];

  factory Song(List<SongStep> steps) =>
      Song._(List.unmodifiable(steps.take(kSongStepsMax)));

  final List<SongStep> steps;

  bool get isEmpty => steps.isEmpty;
  bool get isNotEmpty => steps.isNotEmpty;

  /// How long the whole song lasts, in bars.
  int get bars => steps.fold(0, (sum, step) => sum + step.repeats);

  /// Which pattern bar number [bar] plays. The song loops, so bar seven of a
  /// six-bar song is bar one again — a song that stopped dead at its end
  /// would leave the loops running over silence.
  int patternForBar(int bar) {
    if (isEmpty) return 0;
    var left = bar % bars;
    if (left < 0) left += bars;
    for (final step in steps) {
      if (left < step.repeats) return step.pattern;
      left -= step.repeats;
    }
    return steps.last.pattern;
  }

  /// Which entry of the song bar number [bar] falls in, so the strip can
  /// light the one that is sounding. Null while the song is empty.
  int? indexForBar(int bar) {
    if (isEmpty) return null;
    var left = bar % bars;
    if (left < 0) left += bars;
    for (var i = 0; i < steps.length; i++) {
      if (left < steps[i].repeats) return i;
      left -= steps[i].repeats;
    }
    return steps.length - 1;
  }

  /// Adds one entry at the end. A full song ignores the addition rather than
  /// dropping the entry the player wrote first.
  Song appended(SongStep step) =>
      steps.length >= kSongStepsMax ? this : Song([...steps, step]);

  Song removedAt(int index) => !_isValid(index)
      ? this
      : Song([...steps]..removeAt(index));

  Song withRepeatsAt(int index, int repeats) => !_isValid(index)
      ? this
      : Song([...steps]..[index] = steps[index].withRepeats(repeats));

  /// Swaps the entry at [index] with the one [delta] places away, which is
  /// how a song is reordered: one step at a time, never dragged.
  Song movedAt(int index, int delta) {
    final target = index + delta;
    if (!_isValid(index) || !_isValid(target)) return this;
    final next = [...steps];
    next[index] = steps[target];
    next[target] = steps[index];
    return Song(next);
  }

  bool _isValid(int index) => index >= 0 && index < steps.length;

  List<Map<String, dynamic>> toJson() =>
      steps.map((s) => s.toJson()).toList();

  /// A session written before songs existed comes back with no song, which
  /// is exactly what it had: none.
  factory Song.fromJson(dynamic json) {
    if (json is! List || json.isEmpty) return const Song.empty();
    return Song([
      for (final step in json)
        if (step is Map) SongStep.fromJson(step),
    ]);
  }
}
