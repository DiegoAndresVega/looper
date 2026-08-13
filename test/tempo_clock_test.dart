import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/tempo_clock.dart';
import 'package:looper/core/constants.dart';

/// Every step the clock fired, as `millisecond → key`. Two entries sharing a
/// millisecond went out in the same pass, which is what «sonar juntos» means.
class ClockLog {
  final List<({int at, String key})> hits = [];

  /// Se suma al tiempo que ve el reloj sin que corran los temporizadores: así
  /// se imita volver de segundo plano, con la app parada y el tiempo corriendo.
  Duration skew = Duration.zero;

  List<int> timesOf(String key) =>
      hits.where((h) => h.key == key).map((h) => h.at).toList();
}

/// Runs [body] on a clock whose time is the fake one, so a bar goes by in a
/// single statement and the grid can be checked step by step.
ClockLog onFakeClock(void Function(FakeAsync async, TempoClock clock, ClockLog log) body) {
  final log = ClockLog();
  fakeAsync((async) {
    final clock = TempoClock(
      onStep: (key) => log.hits.add((at: async.elapsed.inMilliseconds, key: key)),
      timeSource: () {
        final start = async.elapsed;
        return () => (async.elapsed - start + log.skew).inMilliseconds;
      },
    );
    body(async, clock, log);
    clock.dispose();
  });
  return log;
}

void main() {
  group('arranque', () {
    test('lo primero que entra suena ya, sin esperar a nada', () {
      final log = onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
      });

      expect(log.timesOf('a'), [0]);
    });

    test('parar y volver a empezar no deja el primer loop mudo', () {
      // El índice de paso se quedaba donde lo dejó la parada anterior, así
      // que el siguiente loop esperaba en silencio hasta alcanzarlo.
      final log = onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
        async.elapse(const Duration(seconds: 3));
        clock.remove('a');
        clock.add('b', kStepsPerBeat);
      });

      expect(log.timesOf('b').first, 3000);
    });
  });

  group('volver de segundo plano', () {
    test('media hora fuera no vuelve como una ráfaga', () {
      onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
        async.elapse(const Duration(seconds: 1));
        final before = log.timesOf('a').length;

        // La app estuvo parada: el tiempo corrió, los temporizadores no.
        log.skew = const Duration(minutes: 30);
        async.elapse(const Duration(milliseconds: 16));

        expect(log.timesOf('a').length - before, lessThanOrEqualTo(2));
      });
    });

    test('y lo que sigue sonando sigue en su sitio', () {
      onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
        clock.add('b', kStepsPerBar);
        async.elapse(const Duration(seconds: 1));

        log.skew = const Duration(minutes: 30);
        async.elapse(const Duration(seconds: 5));

        final a = log.timesOf('a');
        final b = log.timesOf('b');
        expect(b.length, greaterThan(1));
        expect(b.every(a.contains), isTrue,
            reason: 'tras la vuelta, $b se salió del pulso $a');
      });
    });
  });

  group('dos loops a la vez', () {
    test('el segundo espera al compás y desde ahí cae siempre con el primero', () {
      final log = onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
        async.elapse(const Duration(milliseconds: 250));
        clock.add('b', kStepsPerBeat);
        async.elapse(const Duration(seconds: 3));
      });

      final a = log.timesOf('a');
      final b = log.timesOf('b');
      expect(b.length, greaterThan(3));
      expect(b.every(a.contains), isTrue,
          reason: 'b sonó en $b, que no está dentro de $a');
    });

    test('largos distintos comparten el pulso en vez de cruzarse', () {
      final log = onFakeClock((async, clock, log) {
        clock.add('corto', kStepsPerBeat);
        async.elapse(const Duration(milliseconds: 400));
        clock.add('largo', kStepsPerBar);
        async.elapse(const Duration(seconds: 8));
      });

      final corto = log.timesOf('corto');
      final largo = log.timesOf('largo');
      expect(largo.length, greaterThan(1));
      expect(largo.every(corto.contains), isTrue,
          reason: 'el loop largo sonó en $largo, fuera del pulso $corto');
    });

    test('el que espera avisa de que está esperando', () {
      onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBar);
        async.elapse(const Duration(milliseconds: 250));

        clock.add('b', kStepsPerBar);
        expect(clock.isPending('b'), isTrue);
        expect(clock.isPending('a'), isFalse);

        async.elapse(const Duration(seconds: 3));
        expect(clock.isPending('b'), isFalse);
      });
    });
  });

  group('alineación pedida a mano', () {
    test('el secuenciador suena cada paso pero entra en la línea de compás', () {
      final log = onFakeClock((async, clock, log) {
        clock.add('loop', kStepsPerBeat);
        async.elapse(const Duration(milliseconds: 250));
        clock.add('seq', 1, alignTo: kStepsPerBar);
        async.elapse(const Duration(seconds: 4));
      });

      final seq = log.timesOf('seq');
      final loop = log.timesOf('loop');
      // Su primer paso cae en una línea de compás, que también es pulso.
      expect(loop, contains(seq.first));
      // Y a partir de ahí va paso a paso, no de pulso en pulso.
      expect(seq.length, greaterThan(loop.length));
    });
  });

  group('anillo de progreso', () {
    test('va de cero a uno dentro de su propio largo', () {
      onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBeat);
        expect(clock.progressFor('a'), lessThan(0.1));

        async.elapse(Duration(milliseconds: (clock.stepMs * 2).round()));
        expect(clock.progressFor('a'), closeTo(0.5, 0.15));

        // Justo pasada la vuelta: el anillo vuelve a empezar en vez de
        // quedarse clavado arriba.
        async.elapse(Duration(milliseconds: (clock.stepMs * 2).round() + 16));
        expect(clock.progressFor('a'), lessThan(0.2));
      });
    });

    test('el que aún no ha entrado no mueve el anillo', () {
      onFakeClock((async, clock, log) {
        clock.add('a', kStepsPerBar);
        async.elapse(const Duration(milliseconds: 250));
        clock.add('b', kStepsPerBar);

        expect(clock.progressFor('b'), 0);
      });
    });

    test('lo que no está en el reloj no tiene progreso', () {
      onFakeClock((async, clock, log) {
        expect(clock.progressFor('fantasma'), 0);
        expect(clock.isPending('fantasma'), isFalse);
      });
    });
  });
}
