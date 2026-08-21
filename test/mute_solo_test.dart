import 'package:flutter_test/flutter_test.dart';
import 'package:looper/domain/pad_config.dart';

/// El solo no es un silencio.
///
/// El fallo original: `toggleSolo` implementaba el solo escribiendo
/// `muted: true` en todos los demás pads, y al quitarlo escribía
/// `muted: false` en todos. Los silencios que el músico hubiera puesto a mano
/// desaparecían — y como la sesión se autoguarda 800 ms después, el destrozo
/// se persistía a disco.
///
/// La regla correcta es la de cualquier mezclador: el solo vive fuera del pad
/// y manda mientras está puesto; los silencios manuales siguen ahí debajo,
/// esperando a que se quite.
void main() {
  const mudo = PadConfig(soundId: 'caja', muted: true);
  const sonando = PadConfig(soundId: 'bombo');

  group('sin solo', () {
    test('un pad silenciado no suena', () {
      expect(isPadSilenced(pad: mudo, key: '0:1', soloKey: null), isTrue);
    });

    test('un pad normal suena', () {
      expect(isPadSilenced(pad: sonando, key: '0:0', soloKey: null), isFalse);
    });
  });

  group('con solo puesto', () {
    test('el pad en solo suena', () {
      expect(isPadSilenced(pad: sonando, key: '0:0', soloKey: '0:0'), isFalse);
    });

    test('los demás callan aunque no estén silenciados', () {
      expect(isPadSilenced(pad: sonando, key: '0:5', soloKey: '0:0'), isTrue);
    });

    test('el solo manda sobre el silencio propio del pad', () {
      // Poner en solo un pad que estaba silenciado tiene que dejarlo oír:
      // es lo que el dedo acaba de pedir.
      expect(isPadSilenced(pad: mudo, key: '0:1', soloKey: '0:1'), isFalse);
    });

    test('el solo cruza bancos', () {
      expect(isPadSilenced(pad: sonando, key: '2:3', soloKey: '0:0'), isTrue);
      expect(isPadSilenced(pad: sonando, key: '2:3', soloKey: '2:3'), isFalse);
    });
  });

  group('el solo no destruye los silencios manuales', () {
    test('al quitarlo, cada pad vuelve a lo que el músico había puesto', () {
      // Una fila con dos silencios puestos a mano.
      final fila = <String, PadConfig>{
        '0:0': sonando,
        '0:1': mudo,
        '0:2': sonando,
        '0:3': mudo,
      };

      // Con el solo en 0:2 solo se oye ese.
      final conSolo = {
        for (final e in fila.entries)
          e.key: isPadSilenced(pad: e.value, key: e.key, soloKey: '0:2'),
      };
      expect(conSolo, {'0:0': true, '0:1': true, '0:2': false, '0:3': true});

      // Al quitarlo vuelven exactamente los silencios de antes: 0:1 y 0:3.
      final sinSolo = {
        for (final e in fila.entries)
          e.key: isPadSilenced(pad: e.value, key: e.key, soloKey: null),
      };
      expect(sinSolo, {'0:0': false, '0:1': true, '0:2': false, '0:3': true});

      // Y los propios pads siguen siendo los mismos objetos, sin tocar.
      expect(fila['0:1']!.muted, isTrue);
      expect(fila['0:3']!.muted, isTrue);
      expect(fila['0:0']!.muted, isFalse);
    });
  });
}
