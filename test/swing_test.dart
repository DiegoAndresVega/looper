import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/tempo_clock.dart';
import 'package:looper/core/constants.dart';

/// El swing, tal y como lo inventó el MPC-60 en 1988: retrasar *solo* las
/// semicorcheas pares del compás — las que caen en índice impar, contando
/// desde cero. 50 % es recto, 54–58 % es el hip-hop de toda la vida, 66 % ya
/// es tresillo.
///
/// Lo que estos tests protegen por encima de todo es que **las negras no se
/// mueven**: cada par de semicorcheas sigue sumando lo mismo, así que el
/// metrónomo y los bucles de una negra o de una corchea caen exactamente
/// donde caían. Si eso se rompe, el swing deja de ser swing y pasa a ser una
/// app desafinada del tiempo.
void main() {
  const paso = 125.0; // una semicorchea a 120 BPM

  group('sin swing', () {
    test('todos los pasos duran lo mismo', () {
      for (var i = 0; i < 16; i++) {
        expect(swungStepMs(stepMs: paso, swing: 0.5, stepIndex: i),
            closeTo(paso, 0.001));
      }
    });
  });

  group('con swing', () {
    test('el paso par se alarga y el impar se acorta', () {
      final largo = swungStepMs(stepMs: paso, swing: 0.58, stepIndex: 0);
      final corto = swungStepMs(stepMs: paso, swing: 0.58, stepIndex: 1);

      expect(largo, greaterThan(paso));
      expect(corto, lessThan(paso));
      expect(largo, closeTo(paso * 2 * 0.58, 0.001));
      expect(corto, closeTo(paso * 2 * 0.42, 0.001));
    });

    test('cada par de semicorcheas sigue sumando una corchea', () {
      for (final swing in [0.5, 0.54, 0.58, 0.66, 0.75]) {
        for (var par = 0; par < 8; par++) {
          final a = swungStepMs(stepMs: paso, swing: swing, stepIndex: par * 2);
          final b =
              swungStepMs(stepMs: paso, swing: swing, stepIndex: par * 2 + 1);
          expect(a + b, closeTo(paso * 2, 0.001),
              reason: 'el par $par se descuadra con swing $swing');
        }
      }
    });

    test('las negras no se mueven, que es lo que salva al metrónomo', () {
      for (final swing in [0.5, 0.58, 0.66, 0.75]) {
        for (var negra = 0; negra <= 4; negra++) {
          final conSwing = swungSpanMs(
            stepMs: paso,
            swing: swing,
            fromStep: 0,
            count: negra * kStepsPerBeat,
          );
          expect(conSwing, closeTo(paso * negra * kStepsPerBeat, 0.001),
              reason: 'la negra $negra se mueve con swing $swing');
        }
      }
    });

    test('al 66 % la primera semicorchea dura el doble que la segunda', () {
      // Dos tercios contra un tercio: el tresillo.
      final largo = swungStepMs(stepMs: paso, swing: 2 / 3, stepIndex: 0);
      final corto = swungStepMs(stepMs: paso, swing: 2 / 3, stepIndex: 1);

      expect(largo, closeTo(corto * 2, 0.001));
    });

    test('un tramo que empieza en paso impar también cuadra', () {
      final tramo = swungSpanMs(
          stepMs: paso, swing: 0.62, fromStep: 3, count: 8);

      expect(tramo, closeTo(paso * 8, 0.001));
    });

    test('nunca devuelve una duración de cero o negativa', () {
      for (final swing in [kSwingMin, kSwingDefault, kSwingMax]) {
        for (var i = 0; i < 4; i++) {
          expect(swungStepMs(stepMs: paso, swing: swing, stepIndex: i),
              greaterThan(0));
        }
      }
    });
  });

  group('el reloj de tempo con swing', () {
    test('nace recto', () {
      expect(TempoClock(onStep: (_) {}).swing, kSwingDefault);
    });

    test('recorta el swing al rango que tiene sentido tocar', () {
      final clock = TempoClock(onStep: (_) {});

      clock.swing = 0.2;
      expect(clock.swing, kSwingMin);

      clock.swing = 0.99;
      expect(clock.swing, kSwingMax);
    });

    test('con swing la segunda semicorchea llega tarde', () {
      fakeAsync((async) {
        final golpes = <int>[];
        var ahora = 0;
        final clock = TempoClock(
          onStep: (_) => golpes.add(ahora),
          timeSource: () => () => ahora,
        );
        clock.setBpm(120);
        clock.swing = 0.75; // el extremo, para que se vea sin ambigüedad
        clock.add('hat', 1);

        // Avanza el reloj falso de 8 en 8 ms durante una negra larga.
        for (var t = 0; t <= 520; t += kSchedulerTick.inMilliseconds) {
          ahora = t;
          async.elapse(kSchedulerTick);
        }
        clock.dispose();

        // Paso 0 en 0, paso 1 no antes de 125 * 2 * 0.75 = 187,5 ms.
        expect(golpes.length, greaterThanOrEqualTo(3));
        expect(golpes[0], 0);
        expect(golpes[1], greaterThanOrEqualTo(184));
        // Y el paso 2, la corchea, vuelve a caer en su sitio: 250 ms.
        expect(golpes[2], closeTo(250, kSchedulerTick.inMilliseconds));
      });
    });
  });
}
