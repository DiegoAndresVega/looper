import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/voices.dart';
import 'package:looper/audio/wav_encoder.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/data/factory_kit.dart';
import 'package:looper/domain/pad_config.dart';
import 'package:looper/domain/pattern.dart';
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
      // El pad va suelto a propósito: sincronizado es el valor por defecto,
      // así que solo el suelto demuestra que la clave viaja de verdad.
      final original = Session.blank(id: 'x', name: 'Cocina 04')
          .copyWith(bpm: 148)
          .withPad(1, 0,
              const PadConfig(soundId: 's9', synced: false, loopSteps: 32));

      final restored = Session.fromJson(original.toJson());

      expect(restored.name, 'Cocina 04');
      expect(restored.bpm, 148);
      expect(restored.padAt(1, 0).soundId, 's9');
      expect(restored.padAt(1, 0).synced, isFalse);
      expect(restored.padAt(1, 0).loopSteps, 32);
    });

    test('un pad nuevo nace enganchado al tempo', () {
      const pad = PadConfig(soundId: 's1');

      expect(pad.synced, isTrue);
    });

    test('los patrones del secuenciador viajan con la sesión', () {
      final original = Session.blank(id: 'x', name: 'Con patrón').copyWith(
        patterns: [
          Pattern.empty().withNote(0, '0:0').withNote(0, '1:3'),
          ...List.generate(kPatternCount - 1, (_) => Pattern.empty()),
        ],
        activePattern: 3,
      );

      final restored = Session.fromJson(original.toJson());

      expect(restored.patterns.length, kPatternCount);
      expect(restored.patterns.first.at(0), {'0:0', '1:3'});
      expect(restored.activePattern, 3);
    });

    test('una sesión sin patrones se abre con dieciséis vacíos', () {
      final legacy = {
        'id': 'x',
        'name': 'Antigua',
        'bpm': 100,
        'banks': [
          {
            'id': 'A',
            'label': 'Kit',
            'pads': [
              {'soundId': 's1', 'mode': 'loop', 'volume': 0.7, 'synced': false},
              for (var i = 1; i < kPadsPerBank; i++) {'soundId': null},
            ],
          },
          for (final id in ['B', 'C', 'D'])
            {
              'id': id,
              'label': id,
              'pads': [for (var i = 0; i < kPadsPerBank; i++) {'soundId': null}],
            },
        ],
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 1, 2).toIso8601String(),
      };

      final restored = Session.fromJson(legacy);

      expect(restored.padAt(0, 0).soundId, 's1');
      // La clave vieja 'synced' se escribió en falso para todos los pads
      // cuando lo normal era ir suelto. Se ignora: si no, una sesión de antes
      // se quedaría fuera de tempo para siempre.
      expect(restored.padAt(0, 0).synced, isTrue);
      expect(restored.padAt(0, 0).volume, 0.7);
      expect(restored.patterns.length, kPatternCount);
      expect(restored.patterns.every((p) => p.isEmpty), isTrue);
    });
  });

  group('pad', () {
    test('vaciar un pad borra el sonido pero conserva los ajustes', () {
      const pad = PadConfig(soundId: 's1', synced: true, volume: 0.5);

      final cleared = pad.copyWith(clearSound: true);

      expect(cleared.isEmpty, isTrue);
      expect(cleared.synced, isTrue);
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

  group('panorama por pad', () {
    test('un pad nuevo nace en el centro', () {
      expect(const PadConfig().pan, 0);
    });

    test('viaja en el JSON', () {
      final pad = const PadConfig(soundId: 'x', pan: -0.6);

      expect(PadConfig.fromJson(pad.toJson()).pan, closeTo(-0.6, 0.001));
    });

    test('un pad guardado antes del panorama se abre centrado', () {
      final viejo = {
        'soundId': 'x',
        'volume': 0.8,
        'semitones': 0,
        'loopSteps': 16,
        'sync': true,
        'muted': false,
      };

      expect(PadConfig.fromJson(viejo).pan, 0);
    });
  });
}
