import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/voices.dart';
import 'package:looper/audio/wav_encoder.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/data/factory_kit.dart';
import 'package:looper/domain/pad_config.dart';
import 'package:looper/domain/session.dart';

void main() {
  group('kit de fábrica', () {
    test('los dos bancos de fábrica llenan una grilla 4x4', () {
      expect(isFactoryKitWellFormed, isTrue);
      expect(kAllFactoryPads.length, 32);
    });

    test('cada pad de fábrica apunta a una voz que existe', () {
      for (final pad in kAllFactoryPads) {
        expect(kVoices.containsKey(pad.voiceId), isTrue,
            reason: 'falta la voz ${pad.voiceId} de ${pad.name}');
      }
    });

    test('los identificadores de sonido no se repiten', () {
      final ids = kAllFactoryPads.map((p) => p.soundId).toSet();
      expect(ids.length, kAllFactoryPads.length);
    });
  });

  group('síntesis', () {
    test('una voz produce muestras audibles dentro de rango', () {
      final samples = kVoices['kick']!(kSampleRate);

      expect(samples.length, greaterThan(0));
      var peak = 0.0;
      for (final s in samples) {
        expect(s.abs(), lessThanOrEqualTo(1.0));
        if (s.abs() > peak) peak = s.abs();
      }
      expect(peak, greaterThan(0.5), reason: 'el bombo debería sonar fuerte');
    });

    test('el acid suena y no se va de rango', () {
      final samples = kVoices['acid1']!(kSampleRate);

      expect(samples.length, greaterThan(0));
      for (final s in samples) {
        expect(s.isFinite, isTrue);
        expect(s.abs(), lessThanOrEqualTo(1.0));
      }
    });

    test('todas las voces rinden algo audible', () {
      for (final entry in kVoices.entries) {
        final samples = entry.value(kSampleRate);
        var peak = 0.0;
        for (final s in samples) {
          if (s.abs() > peak) peak = s.abs();
        }
        expect(peak, greaterThan(0.1), reason: '${entry.key} sale mudo');
      }
    });

    test('el WAV lleva cabecera RIFF y el tamaño de datos correcto', () {
      final samples = kVoices['hat']!(kSampleRate);
      final bytes = encodeWav(samples, sampleRate: kSampleRate);

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, 44 + samples.length * 2);
    });
  });

  group('sesión', () {
    test('una sesión nueva trae cuatro bancos vacíos', () {
      final session = Session.blank(id: 'x', name: 'Prueba');

      expect(session.banks.length, kBankCount);
      expect(session.filledPadCount, 0);
      expect(session.usedBankCount, 0);
    });

    test('cambiar un pad devuelve una sesión nueva sin tocar la original', () {
      final original = Session.blank(id: 'x', name: 'Prueba');

      final updated = original.withPad(0, 3, const PadConfig(soundId: 's1'));

      expect(original.padAt(0, 3).isEmpty, isTrue);
      expect(updated.padAt(0, 3).soundId, 's1');
    });

    test('el primer hueco libre empieza por el banco C', () {
      final session = Session.blank(id: 'x', name: 'Prueba');

      final free = session.nextFreeSlot;

      expect(free?.bank, 2);
      expect(free?.slot, 0);
    });

    test('la sesión sobrevive a un viaje por JSON', () {
      final original = Session.blank(id: 'x', name: 'Cocina 04')
          .copyWith(bpm: 148)
          .withPad(1, 0, const PadConfig(soundId: 's9', mode: PadMode.loop));

      final restored = Session.fromJson(original.toJson());

      expect(restored.name, 'Cocina 04');
      expect(restored.bpm, 148);
      expect(restored.padAt(1, 0).soundId, 's9');
      expect(restored.padAt(1, 0).mode, PadMode.loop);
    });
  });

  group('pad', () {
    test('vaciar un pad borra el sonido pero conserva los ajustes', () {
      const pad = PadConfig(soundId: 's1', mode: PadMode.loop, volume: 0.5);

      final cleared = pad.copyWith(clearSound: true);

      expect(cleared.isEmpty, isTrue);
      expect(cleared.mode, PadMode.loop);
      expect(cleared.volume, 0.5);
    });

    test('un banco encuentra su primer hueco libre', () {
      final bank = Bank.blank('A', 'Kit')
          .withPad(0, const PadConfig(soundId: 's1'))
          .withPad(1, const PadConfig(soundId: 's2'));

      expect(bank.firstFreeSlot, 2);
      expect(bank.filledCount, 2);
    });

    test('llenar un pad no muta el banco original', () {
      final original = Bank.blank('A', 'Kit');

      final updated = original.withPad(5, const PadConfig(soundId: 's1'));

      expect(original.pads[5].isEmpty, isTrue);
      expect(updated.pads[5].soundId, 's1');
    });
  });
}
