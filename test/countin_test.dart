import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/tempo_clock.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/state/sequencer.dart';

/// Dos arreglos que van juntos porque resuelven el mismo problema: no había
/// forma de saber dónde empieza el compás.
///
/// El clic sonaba idéntico en las cuatro negras, así que no decía cuál era el
/// uno — que es justo para lo que se enciende un metrónomo. Y el REC empezaba
/// a escribir en el paso donde estuviera la cabeza, sin margen, así que había
/// que anticiparse al botón.
void main() {
  group('el acento del metrónomo', () {
    test('el uno del compás lleva acento y los demás no', () {
      expect(isDownbeat(0), isTrue);
      expect(isDownbeat(kStepsPerBeat), isFalse);
      expect(isDownbeat(kStepsPerBeat * 2), isFalse);
      expect(isDownbeat(kStepsPerBeat * 3), isFalse);
    });

    test('vuelve a acentuar en el compás siguiente', () {
      expect(isDownbeat(kStepsPerBar), isTrue);
      expect(isDownbeat(kStepsPerBar * 3), isTrue);
      expect(isDownbeat(kStepsPerBar + kStepsPerBeat), isFalse);
    });
  });

  group('la cuenta atrás antes de escribir', () {
    Sequencer buildSequencer() => Sequencer(
          onNotes: (_) {},
          onPatternsChanged: () {},
        )..load([Pattern.empty()], 0);

    test('el REC no escribe hasta que pasa el compás de cortesía', () {
      final seq = buildSequencer()..toggleOn();

      seq.toggleRecord();

      expect(seq.isCountingIn, isTrue);
      expect(seq.isRecording, isFalse,
          reason: 'todavía no se escribe: se está contando');
    });

    test('la cuenta dura exactamente un compás', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      for (var i = 0; i < kStepsPerBar - 1; i++) {
        seq.tick();
        expect(seq.isCountingIn, isTrue, reason: 'se cortó en el paso $i');
      }
      seq.tick();

      expect(seq.isCountingIn, isFalse);
      expect(seq.isRecording, isTrue);
    });

    test('escribe desde el paso uno, no desde donde estuviera la cabeza', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();
      for (var i = 0; i < kStepsPerBar; i++) {
        seq.tick();
      }

      seq.tap('0:0');

      expect(seq.pattern.at(0), {'0:0'});
    });

    test('un pad tocado durante la cuenta no se escribe', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      seq.tap('0:0');

      expect(seq.pattern.isEmpty, isTrue);
    });

    test('la cuenta va diciendo por qué negra pasa', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      expect(seq.countInBeat, 1);
      for (var i = 0; i < kStepsPerBeat; i++) {
        seq.tick();
      }
      expect(seq.countInBeat, 2);
    });

    test('volver a pulsar REC durante la cuenta la cancela', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      seq.toggleRecord();

      expect(seq.isCountingIn, isFalse);
      expect(seq.isRecording, isFalse);
    });

    test('parar el secuenciador cancela la cuenta', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      seq.toggleOn();

      expect(seq.isCountingIn, isFalse);
    });

    test('dar al play durante la cuenta la cancela', () {
      final seq = buildSequencer()..toggleOn();
      seq.toggleRecord();

      seq.togglePlay();

      expect(seq.isCountingIn, isFalse);
      expect(seq.isPlaying, isTrue);
    });
  });
}
