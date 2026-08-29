import 'package:flutter_test/flutter_test.dart';
import 'package:looper/domain/pad_config.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/domain/scene.dart';
import 'package:looper/domain/session.dart';
import 'package:looper/domain/song.dart';

/// Duplicar una sesión tiene que traerse *todo* lo que no es su identidad.
/// El fallo original fue que `duplicate()` enumeraba campos a mano y se dejó
/// `chainLength`, así que la copia de una sesión de ocho compases volvía a uno
/// sin avisar. Estos tests comparan el JSON entero para que el próximo campo
/// que se añada a `Session` no pueda repetir el olvido.
void main() {
  /// Una sesión con todos los campos movidos de su valor por defecto: si algo
  /// no viaja en la copia, se nota.
  Session buildFullSession() {
    var session = Session.blank(id: 'origen', name: 'Original');
    session = session
        .copyWith(
          bpm: 128,
          activePattern: 7,
          chainLength: 8,
          song: const Song.empty()
              .appended(const SongStep(pattern: 7, repeats: 2))
              .appended(const SongStep(pattern: 3)),
          songMode: true,
        )
        .withScene(1, Scene.capture(loops: {'0:3', '2:11'}, pattern: 7))
        .withPad(0, 3, const PadConfig(soundId: 'bombo', volume: 0.6))
        .withPad(2, 11, const PadConfig(soundId: 'voz', semitones: -5));

    final patterns = List<Pattern>.of(session.patterns);
    patterns[7] = Pattern.empty().toggled(4, '0:3').toggled(12, '2:11');
    return session.copyWith(patterns: patterns);
  }

  /// Todo menos la identidad: lo que una copia debe conservar intacto.
  Map<String, dynamic> withoutIdentity(Session s) {
    final json = Map<String, dynamic>.of(s.toJson());
    json.remove('id');
    json.remove('name');
    json.remove('createdAt');
    json.remove('updatedAt');
    return json;
  }

  group('duplicar una sesión', () {
    test('conserva todos los campos salvo la identidad', () {
      final original = buildFullSession();

      final copia = original.duplicateAs(id: 'copia', name: 'Original copia');

      expect(withoutIdentity(copia), equals(withoutIdentity(original)));
    });

    test('conserva la cadena de patrones', () {
      final original = buildFullSession();

      final copia = original.duplicateAs(id: 'copia', name: 'Copia');

      expect(copia.chainLength, 8);
      expect(copia.activePattern, 7);
    });

    test('estrena identidad propia', () {
      final original = buildFullSession();

      final copia = original.duplicateAs(id: 'copia', name: 'Otra');

      expect(copia.id, 'copia');
      expect(copia.name, 'Otra');
      expect(copia.id, isNot(original.id));
    });

    test('no toca la sesión de origen', () {
      final original = buildFullSession();
      final antes = original.toJson();

      original.duplicateAs(id: 'copia', name: 'Copia');

      expect(original.toJson(), equals(antes));
    });
  });
}
