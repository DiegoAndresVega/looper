import '../core/constants.dart';

/// Loop lengths, in 16th notes, offered when a pad is synced to the tempo.
/// The list always contains the length the pad already has, so a factory pad
/// set to half a beat still shows what it is instead of nothing.
List<int> loopLengthChoices(int current) {
  final choices = {...kLoopLengthChoices, current}.toList()..sort();
  return List.unmodifiable(choices);
}

/// A loop length written in beats, the unit the control surface already uses.
/// Halves get a fraction rather than a decimal: '½' reads faster than '0.5'.
String loopLengthLabel(int steps) {
  if (steps % kStepsPerBeat == 0) return '${steps ~/ kStepsPerBeat}';

  final halfBeats = steps * 2 / kStepsPerBeat;
  if (halfBeats == halfBeats.roundToDouble()) {
    final whole = halfBeats ~/ 2;
    return whole == 0 ? '½' : '$whole½';
  }
  return (steps / kStepsPerBeat).toStringAsFixed(2);
}
