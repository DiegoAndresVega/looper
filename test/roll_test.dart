import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/tempo_clock.dart';
import 'package:looper/core/constants.dart';

/// El roll tenía dos divisiones declaradas en `kRollDivisions` y ninguna
/// conectada: el motor repetía siempre en semicorcheas. Estos tests fijan la
/// aritmética de la rejilla, que es la misma que usa el reloj de tempo, para
/// que las dos divisiones caigan exactamente donde caen sus pasos.
void main() {
  group('la rejilla de pasos', () {
    test('una semicorchea a 120 BPM dura 125 ms', () {
      // 120 BPM = 500 ms por negra; una negra son cuatro semicorcheas.
      expect(stepMsAt(120), closeTo(125, 0.001));
    });

    test('el paso se acorta al subir el tempo', () {
      expect(stepMsAt(240), closeTo(stepMsAt(120) / 2, 0.001));
    });

    test('coincide con el reloj de tempo', () {
      final clock = TempoClock(onStep: (_) {});
      clock.setBpm(92);

      expect(clock.stepMs, closeTo(stepMsAt(92), 0.001));
    });
  });

  group('divisiones del roll', () {
    test('las dos divisiones son corchea y semicorchea', () {
      expect(kRollDivisions, [2, 1]);
    });

    test('todas caben en un compás y son pasos enteros', () {
      for (final steps in kRollDivisions) {
        expect(steps, greaterThan(0));
        expect(kStepsPerBar % steps, 0,
            reason: 'una división de $steps pasos no cuadra con el compás');
      }
    });

    test('la corchea dura el doble que la semicorchea', () {
      final corchea = rollIntervalFor(bpm: 120, steps: 2);
      final semicorchea = rollIntervalFor(bpm: 120, steps: 1);

      expect(corchea.inMicroseconds, semicorchea.inMicroseconds * 2);
    });

    test('a 120 BPM la semicorchea son 125 ms y la corchea 250 ms', () {
      expect(rollIntervalFor(bpm: 120, steps: 1).inMicroseconds, 125000);
      expect(rollIntervalFor(bpm: 120, steps: 2).inMicroseconds, 250000);
    });

    test('el intervalo nunca es cero, ni al tempo máximo', () {
      for (final steps in kRollDivisions) {
        final intervalo = rollIntervalFor(bpm: kBpmMax, steps: steps);
        expect(intervalo.inMicroseconds, greaterThan(0));
      }
    });

    test('etiqueta cada división como se lee en música', () {
      expect(rollDivisionLabel(2), '1/8');
      expect(rollDivisionLabel(1), '1/16');
    });
  });
}
