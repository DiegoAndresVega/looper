import '../core/constants.dart';

/// A pattern is one bar cut into sixteen steps. Each step holds the pads that
/// fire on it — none, one, or several at once — and a step with nothing in it
/// is a rest, not a gap in the list.
///
/// Notes are pad keys ('bank:slot'), so a pattern can pull a kick from bank A
/// and an acid line from bank B without caring which bank is on screen.
class Pattern {
  Pattern(List<Set<String>> steps)
      : steps = List.unmodifiable([
          for (var i = 0; i < kPatternSteps; i++)
            Set<String>.unmodifiable(i < steps.length ? steps[i] : const {}),
        ]);

  factory Pattern.empty() =>
      Pattern(List.generate(kPatternSteps, (_) => <String>{}));

  final List<Set<String>> steps;

  Set<String> at(int step) =>
      _isValid(step) ? steps[step] : const <String>{};

  bool get isEmpty => steps.every((step) => step.isEmpty);

  /// How many steps carry at least one note. Used to tell a written pattern
  /// from an empty one at a glance.
  int get filledSteps => steps.where((step) => step.isNotEmpty).length;

  bool has(int step, String note) => at(step).contains(note);

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

  Pattern clearedStep(int step) =>
      _isValid(step) ? _replace(step, <String>{}) : this;

  Pattern cleared() => Pattern.empty();

  Pattern _replace(int step, Set<String> notes) {
    final next = List<Set<String>>.of(steps);
    next[step] = notes;
    return Pattern(next);
  }

  bool _isValid(int step) => step >= 0 && step < kPatternSteps;

  List<List<String>> toJson() =>
      steps.map((step) => step.toList()..sort()).toList();

  factory Pattern.fromJson(List<dynamic> json) {
    return Pattern([
      for (final step in json)
        {...(step as List<dynamic>).map((note) => note as String)},
    ]);
  }
}
