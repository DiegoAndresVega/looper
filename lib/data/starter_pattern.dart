import '../core/constants.dart';
import '../domain/pattern.dart';

/// Pad keys of bank A, by the name they wear on screen.
const String _kick = '0:0';
const String _snare = '0:1';
const String _hat = '0:2';
const String _clap = '0:3';
const String _bass = '0:8';

/// The two bars the app opens with already written.
///
/// The README says «cero onboarding», and the alternative to a tour of coach
/// marks is not a shorter tour: it is something already playing that can be
/// taken apart. A first-time player presses SEQ and PLAY and hears a beat —
/// and every one of these notes is a pad they can lift out to see what it was
/// doing.
///
/// It is deliberately plain: a four-on-the-floor with the snare on two and
/// four. Nothing clever, because the point is that it is legible, and the
/// second pattern is the first one with two things changed so the difference
/// between P1 and P2 is audible the first time the chain runs.
List<Pattern> starterPatterns() {
  var beat = Pattern.empty();
  for (final step in [0, 4, 8, 12]) {
    beat = beat.withNote(step, _kick);
  }
  for (final step in [4, 12]) {
    beat = beat.withNote(step, _snare);
  }
  // Eighth-note hats, with the off-beats held back so the bar breathes
  // instead of reading as a machine.
  for (var step = 0; step < kPatternSteps; step += 2) {
    beat = beat.withNote(step, _hat);
    if (step % 4 != 0) beat = beat.withVelocity(step, 0.62);
  }

  var variation = beat.withNote(14, _clap).withNote(2, _bass);
  variation = variation.withProbability(14, 0.5).withRatchet(2, 2);

  return [beat, variation];
}
