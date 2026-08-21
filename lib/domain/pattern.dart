import '../core/constants.dart';

/// A pattern is one bar cut into sixteen steps. Each step holds the pads that
/// fire on it — none, one, or several at once — and a step with nothing in it
/// is a rest, not a gap in the list.
///
/// Notes are pad keys ('bank:slot'), so a pattern can pull a kick from bank A
/// and an acid line from bank B without caring which bank is on screen.
class Pattern {
  Pattern(
    List<Set<String>> steps, {
    List<double>? velocities,
    List<double>? probabilities,
    List<double>? nudges,
    List<int>? ratchets,
  })  : steps = List.unmodifiable([
          for (var i = 0; i < kPatternSteps; i++)
            Set<String>.unmodifiable(i < steps.length ? steps[i] : const {}),
        ]),
        velocities = _layer(velocities, kVelocityMax,
            (v) => v.clamp(kVelocityMin, kVelocityMax)),
        probabilities = _layer(probabilities, 1.0,
            (v) => v.clamp(kProbabilityMin, 1.0)),
        nudges = _layer(nudges, 0.0, (v) => v.clamp(-kNudgeMax, kNudgeMax)),
        ratchets = _layer(ratchets, 1, (v) => v.clamp(1, kRatchetMax));

  /// Sixteen values that always exist, each clamped to its range. Every layer
  /// follows this shape so a step never has to be asked whether it has one.
  static List<T> _layer<T>(List<T>? raw, T fallback, T Function(T) clamp) =>
      List.unmodifiable([
        for (var i = 0; i < kPatternSteps; i++)
          raw != null && i < raw.length ? clamp(raw[i]) : fallback,
      ]);

  factory Pattern.empty() =>
      Pattern(List.generate(kPatternSteps, (_) => <String>{}));

  final List<Set<String>> steps;

  /// How hard each step hits, 0..1.
  final List<double> velocities;

  /// How likely each step is to sound this time round, [kProbabilityMin]..1.
  /// One means certain, and certain steps never roll the dice.
  final List<double> probabilities;

  /// How far off the grid each step plays, in fractions of a step. Negative
  /// is early, positive is late, zero is the machine.
  final List<double> nudges;

  /// How many hits each step packs, 1..[kRatchetMax]. One is a normal step;
  /// more subdivides it into a roll.
  final List<int> ratchets;

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

  double probabilityAt(int step) =>
      _isValid(step) ? probabilities[step] : 1.0;

  double nudgeAt(int step) => _isValid(step) ? nudges[step] : 0.0;

  int ratchetAt(int step) => _isValid(step) ? ratchets[step] : 1;

  Pattern withVelocity(int step, double velocity) => !_isValid(step)
      ? this
      : _withLayers(velocities: _put(velocities, step, velocity));

  Pattern withProbability(int step, double probability) => !_isValid(step)
      ? this
      : _withLayers(probabilities: _put(probabilities, step, probability));

  Pattern withNudge(int step, double nudge) => !_isValid(step)
      ? this
      : _withLayers(nudges: _put(nudges, step, nudge));

  Pattern withRatchet(int step, int ratchet) => !_isValid(step)
      ? this
      : _withLayers(ratchets: _put(ratchets, step, ratchet));

  static List<T> _put<T>(List<T> layer, int step, T value) =>
      List<T>.of(layer)..[step] = value;

  Pattern _withLayers({
    List<double>? velocities,
    List<double>? probabilities,
    List<double>? nudges,
    List<int>? ratchets,
  }) {
    return Pattern(
      steps,
      velocities: velocities ?? this.velocities,
      probabilities: probabilities ?? this.probabilities,
      nudges: nudges ?? this.nudges,
      ratchets: ratchets ?? this.ratchets,
    );
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

  /// Emptying a step takes its layers with it: the next note written there
  /// starts from neutral, not from whatever the last one was set to.
  Pattern clearedStep(int step) {
    if (!_isValid(step)) return this;
    final nextSteps = List<Set<String>>.of(steps);
    nextSteps[step] = <String>{};
    return Pattern(
      nextSteps,
      velocities: _put(velocities, step, kVelocityMax),
      probabilities: _put(probabilities, step, 1.0),
      nudges: _put(nudges, step, 0.0),
      ratchets: _put(ratchets, step, 1),
    );
  }

  Pattern cleared() => Pattern.empty();

  Pattern _replace(int step, Set<String> notes) {
    final next = List<Set<String>>.of(steps);
    next[step] = notes;
    return Pattern(
      next,
      velocities: velocities,
      probabilities: probabilities,
      nudges: nudges,
      ratchets: ratchets,
    );
  }

  bool _isValid(int step) => step >= 0 && step < kPatternSteps;

  Map<String, dynamic> toJson() => {
        'steps': steps.map((step) => step.toList()..sort()).toList(),
        'velocities': velocities,
        'probabilities': probabilities,
        'nudges': nudges,
        'ratchets': ratchets,
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

    List<double>? doubles(String key) => json is Map
        ? (json[key] as List<dynamic>?)
            ?.map((v) => (v as num).toDouble())
            .toList()
        : null;

    return Pattern(
      [
        for (final step in rawSteps)
          {...(step as List<dynamic>).map((note) => note as String)},
      ],
      velocities: rawVelocities?.map((v) => (v as num).toDouble()).toList(),
      probabilities: doubles('probabilities'),
      nudges: doubles('nudges'),
      ratchets: json is Map
          ? (json['ratchets'] as List<dynamic>?)
              ?.map((v) => (v as num).toInt())
              .toList()
          : null,
    );
  }
}
