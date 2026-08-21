import '../core/constants.dart';

/// A pattern is one bar cut into sixteen steps. Each step holds the pads that
/// fire on it — none, one, or several at once — and a step with nothing in it
/// is a rest, not a gap in the list.
///
/// Notes are pad keys ('bank:slot'), so a pattern can pull a kick from bank A
/// and an acid line from bank B without caring which bank is on screen.
class Pattern {
  Pattern(List<Set<String>> steps, [List<double>? velocities])
      : steps = List.unmodifiable([
          for (var i = 0; i < kPatternSteps; i++)
            Set<String>.unmodifiable(i < steps.length ? steps[i] : const {}),
        ]),
        velocities = List.unmodifiable([
          for (var i = 0; i < kPatternSteps; i++)
            velocities != null && i < velocities.length
                ? velocities[i].clamp(kVelocityMin, kVelocityMax)
                : kVelocityMax,
        ]);

  factory Pattern.empty() =>
      Pattern(List.generate(kPatternSteps, (_) => <String>{}));

  final List<Set<String>> steps;

  /// How hard each step hits, 0..1. Sixteen values that always exist, so a
  /// step never has to be asked whether it has an accent before it can play.
  final List<double> velocities;

  Set<String> at(int step) =>
      _isValid(step) ? steps[step] : const <String>{};

  bool get isEmpty => steps.every((step) => step.isEmpty);

  /// How many steps carry at least one note. Used to tell a written pattern
  /// from an empty one at a glance.
  int get filledSteps => steps.where((step) => step.isNotEmpty).length;

  bool has(int step, String note) => at(step).contains(note);

  /// How hard [step] hits. Full strength for a step that was never touched,
  /// and for one that does not exist.
  double velocityAt(int step) =>
      _isValid(step) ? velocities[step] : kVelocityMax;

  /// Whether anything in here is quieter than full. Drives whether the pads
  /// bother drawing accent bars at all.
  bool get hasAccents => velocities.any((v) => v < kVelocityMax);

  Pattern withVelocity(int step, double velocity) {
    if (!_isValid(step)) return this;
    final next = List<double>.of(velocities);
    next[step] = velocity.clamp(kVelocityMin, kVelocityMax);
    return Pattern(steps, next);
  }

  Pattern withNote(int step, String note) {
    if (!_isValid(step) || has(step, note)) return this;
    return _replace(step, {...steps[step], note});
  }

  Pattern withoutNote(int step, String note) {
    if (!_isValid(step) || !has(step, note)) return this;
    return _replace(step, {...steps[step]}..remove(note));
  }

  Pattern toggled(int step, String note) =>
      has(step, note) ? withoutNote(step, note) : withNote(step, note);

  /// Emptying a step takes its accent with it: the next note written there
  /// starts from full, not from whatever the last one was set to.
  Pattern clearedStep(int step) {
    if (!_isValid(step)) return this;
    final nextVelocities = List<double>.of(velocities);
    nextVelocities[step] = kVelocityMax;
    final nextSteps = List<Set<String>>.of(steps);
    nextSteps[step] = <String>{};
    return Pattern(nextSteps, nextVelocities);
  }

  Pattern cleared() => Pattern.empty();

  Pattern _replace(int step, Set<String> notes) {
    final next = List<Set<String>>.of(steps);
    next[step] = notes;
    return Pattern(next, velocities);
  }

  bool _isValid(int step) => step >= 0 && step < kPatternSteps;

  Map<String, dynamic> toJson() => {
        'steps': steps.map((step) => step.toList()..sort()).toList(),
        'velocities': velocities,
      };

  /// Reads both shapes. Patterns written before accents existed are a bare
  /// list of steps; they come back at full strength, which is exactly how
  /// they sounded when they were saved.
  factory Pattern.fromJson(dynamic json) {
    final List<dynamic> rawSteps;
    List<dynamic>? rawVelocities;

    // Map, not Map<String, dynamic>: what comes back off disk has been
    // through jsonDecode, and the exact generic type is not worth trusting.
    if (json is Map) {
      rawSteps = json['steps'] as List<dynamic>? ?? const [];
      rawVelocities = json['velocities'] as List<dynamic>?;
    } else if (json is List) {
      rawSteps = json;
    } else {
      return Pattern.empty();
    }

    return Pattern(
      [
        for (final step in rawSteps)
          {...(step as List<dynamic>).map((note) => note as String)},
      ],
      rawVelocities?.map((v) => (v as num).toDouble()).toList(),
    );
  }
}
