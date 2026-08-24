import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/palette.dart';
import 'package:looper/domain/midi_map.dart';
import 'package:looper/domain/midi_target.dart';

/// El mapa del controlador: qué mando físico mueve qué, y que sobreviva a
/// cerrar la app. Se prueba sin cable porque no hay cable en juego — son
/// números de control y parámetros.
void main() {
  const filtroMaestro = MidiTarget(MidiParam.masterCutoff);
  const volumenMaestro = MidiTarget(MidiParam.masterVolume);
  final filtroPercusion =
      MidiTarget.bus(MidiParam.busCutoff, SoundFamily.percussion);
  final filtroVoz = MidiTarget.bus(MidiParam.busCutoff, SoundFamily.voice);

  group('casar un mando', () {
    test('un mando aprendido mueve su parámetro', () {
      const mapa = MidiMap.empty();

      final casado = mapa.learn(21, filtroMaestro);

      expect(casado.targetFor(21), filtroMaestro);
      expect(casado.controllerFor(filtroMaestro), 21);
    });

    test('un mando sin aprender no mueve nada', () {
      expect(const MidiMap.empty().targetFor(21), isNull);
    });

    test('un mando solo mueve una cosa', () {
      // Aprender otra cosa en el mismo mando rompe el matrimonio anterior: un
      // mando que mueve dos parámetros es un mando peleándose consigo mismo.
      final mapa = const MidiMap.empty()
          .learn(21, filtroMaestro)
          .learn(21, volumenMaestro);

      expect(mapa.length, 1);
      expect(mapa.targetFor(21), volumenMaestro);
      expect(mapa.controllerFor(filtroMaestro), isNull);
    });

    test('un parámetro solo obedece a un mando', () {
      // Si no, el mando olvidado sigue dando saltos al valor al rozarlo.
      final mapa = const MidiMap.empty()
          .learn(21, filtroMaestro)
          .learn(22, filtroMaestro);

      expect(mapa.length, 1);
      expect(mapa.targetFor(21), isNull);
      expect(mapa.targetFor(22), filtroMaestro);
    });

    test('el bus de cada familia es un destino distinto', () {
      final mapa = const MidiMap.empty()
          .learn(21, filtroPercusion)
          .learn(22, filtroVoz);

      expect(mapa.length, 2);
      expect(mapa.targetFor(21), filtroPercusion);
      expect(mapa.targetFor(22), filtroVoz);
    });

    test('aprender no toca el mapa de antes', () {
      const antes = MidiMap.empty();

      antes.learn(21, filtroMaestro);

      expect(antes.isEmpty, isTrue);
    });

    test('olvidar deja lo demás en su sitio', () {
      final mapa = const MidiMap.empty()
          .learn(21, filtroMaestro)
          .learn(22, volumenMaestro)
          .forget(filtroMaestro);

      expect(mapa.length, 1);
      expect(mapa.targetFor(22), volumenMaestro);
    });

    test('las asignaciones salen ordenadas por número de control', () {
      final mapa = const MidiMap.empty()
          .learn(48, volumenMaestro)
          .learn(12, filtroMaestro);

      expect(mapa.bindings.map((b) => b.controller), [12, 48]);
    });
  });

  group('el viaje a disco', () {
    test('el mapa vuelve entero después de un jsonEncode de verdad', () {
      // Por el JSON de verdad, no por toJson/fromJson a secas: un mapa con
      // claves enteras sobrevive a lo segundo y se rompe en lo primero.
      final mapa = const MidiMap.empty()
          .learn(21, filtroMaestro)
          .learn(22, filtroPercusion)
          .learn(23, const MidiTarget(MidiParam.padVolume));

      final vuelta = MidiMap.fromJson(
        jsonDecode(jsonEncode(mapa.toJson())) as Map<String, dynamic>,
      );

      expect(vuelta, mapa);
    });

    test('todos los destinos posibles saben escribirse y leerse', () {
      for (final param in MidiParam.values) {
        final destinos = param.needsFamily
            ? [for (final f in SoundFamily.values) MidiTarget(param, family: f)]
            : [MidiTarget(param)];
        for (final destino in destinos) {
          expect(MidiTarget.parse(destino.id), destino, reason: destino.id);
        }
      }
    });

    test('un destino que esta versión no conoce se descarta sin más', () {
      final vuelta = MidiMap.fromJson({
        '21': 'masterCutoff',
        '22': 'unaFuncionDelFuturo',
        '23': 'busCutoff:trombones',
        'no-es-un-numero': 'masterVolume',
        '999': 'masterVolume',
      });

      expect(vuelta.length, 1);
      expect(vuelta.targetFor(21), filtroMaestro);
    });

    test('un parámetro de bus sin familia no es un destino', () {
      expect(MidiTarget.parse('busCutoff'), isNull);
      expect(MidiTarget.parse('masterCutoff:percussion'), isNull);
    });
  });

  group('cómo se llama cada destino', () {
    test('un destino de bus se llama por su familia', () {
      expect(filtroPercusion.label, 'Filtro · Percusión');
    });

    test('los demás se llaman por dónde viven', () {
      expect(filtroMaestro.label, 'Filtro · Maestro');
      expect(const MidiTarget(MidiParam.padVolume).label, 'Vol · Pad');
      expect(const MidiTarget(MidiParam.scaleRoot).label, 'Tónica · Escala');
    });
  });
}
