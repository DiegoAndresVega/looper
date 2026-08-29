import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/song.dart';

void main() {
  group('la canción vacía', () {
    test('no tiene compases y no manda sobre nadie', () {
      const song = Song.empty();

      expect(song.isEmpty, isTrue);
      expect(song.bars, 0);
      expect(song.patternForBar(0), 0);
      expect(song.patternForBar(7), 0);
    });
  });

  group('el recorrido', () {
    test('los compases son la suma de las repeticiones', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0, repeats: 2))
          .appended(const SongStep(pattern: 2, repeats: 4));

      expect(song.bars, 6);
    });

    test('cada compás cae en el patrón que le toca', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0, repeats: 2))
          .appended(const SongStep(pattern: 2));

      expect(song.patternForBar(0), 0);
      expect(song.patternForBar(1), 0);
      expect(song.patternForBar(2), 2);
    });

    test('pasado el último compás vuelve a empezar', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0, repeats: 2))
          .appended(const SongStep(pattern: 2));

      expect(song.patternForBar(3), 0);
      expect(song.patternForBar(5), 2);
      expect(song.patternForBar(300), 0);
    });

    test('un compás negativo no rompe nada', () {
      final song = const Song.empty().appended(const SongStep(pattern: 3));

      expect(song.patternForBar(-1), 3);
    });
  });

  group('los límites', () {
    test('las repeticiones se recortan al rango', () {
      expect(const SongStep(pattern: 0, repeats: 0).repeats, 1);
      expect(const SongStep(pattern: 0, repeats: 99).repeats, kSongRepeatMax);
    });

    test('un patrón que no existe se recorta al que sí', () {
      expect(const SongStep(pattern: -3).pattern, 0);
      expect(const SongStep(pattern: 99).pattern, kPatternCount - 1);
    });

    test('la canción no crece más allá del tope', () {
      var song = const Song.empty();
      for (var i = 0; i < kSongStepsMax + 5; i++) {
        song = song.appended(const SongStep(pattern: 1));
      }

      expect(song.steps.length, kSongStepsMax);
    });
  });

  group('editar sin mutar', () {
    test('añadir devuelve otra canción y deja la primera como estaba', () {
      const first = Song.empty();

      final second = first.appended(const SongStep(pattern: 4));

      expect(first.isEmpty, isTrue);
      expect(second.steps.length, 1);
    });

    test('quitar un paso deja el resto en su orden', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0))
          .appended(const SongStep(pattern: 1))
          .appended(const SongStep(pattern: 2));

      final next = song.removedAt(1);

      expect(next.steps.map((s) => s.pattern), [0, 2]);
      expect(song.steps.length, 3);
    });

    test('mover un paso lo intercambia con su vecino', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0))
          .appended(const SongStep(pattern: 1));

      expect(song.movedAt(0, 1).steps.map((s) => s.pattern), [1, 0]);
      expect(song.movedAt(1, -1).steps.map((s) => s.pattern), [1, 0]);
    });

    test('mover fuera de la lista no hace nada', () {
      final song = const Song.empty().appended(const SongStep(pattern: 0));

      expect(song.movedAt(0, -1).steps.map((s) => s.pattern), [0]);
      expect(song.movedAt(0, 1).steps.map((s) => s.pattern), [0]);
    });

    test('cambiar las repeticiones solo toca ese paso', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0))
          .appended(const SongStep(pattern: 1));

      final next = song.withRepeatsAt(1, 4);

      expect(next.steps[0].repeats, 1);
      expect(next.steps[1].repeats, 4);
      expect(song.steps[1].repeats, 1);
    });
  });

  group('el viaje a disco', () {
    test('una canción va y vuelve entera pasando por el texto', () {
      final song = const Song.empty()
          .appended(const SongStep(pattern: 0, repeats: 2))
          .appended(const SongStep(pattern: 5, repeats: 3));

      final back = Song.fromJson(
        jsonDecode(jsonEncode(song.toJson())) as List<dynamic>,
      );

      expect(back.steps.map((s) => s.pattern), [0, 5]);
      expect(back.steps.map((s) => s.repeats), [2, 3]);
    });

    test('lo que no es una canción vuelve vacío', () {
      expect(Song.fromJson(null).isEmpty, isTrue);
      expect(Song.fromJson(const []).isEmpty, isTrue);
    });
  });
}
