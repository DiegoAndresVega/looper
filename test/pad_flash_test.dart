import 'package:flutter_test/flutter_test.dart';
import 'package:looper/state/pad_flashes.dart';

/// El destello del golpe. El pintor del pad sabía dibujarlo desde el primer
/// día —lavado entero y nombre en claro— y nadie lo producía nunca: un pad
/// sonando se veía igual que un pad parado.
void main() {
  /// Un reloj de mentira: las pruebas mueven el tiempo, no lo esperan.
  ({PadFlashes flashes, void Function(int ms) advance}) build() {
    var now = DateTime(2026);
    final flashes = PadFlashes(
      life: const Duration(milliseconds: 100),
      now: () => now,
    );
    return (
      flashes: flashes,
      advance: (ms) => now = now.add(Duration(milliseconds: ms)),
    );
  }

  group('encender y apagarse solo', () {
    test('un pad que suena queda encendido', () {
      final t = build();

      t.flashes.fire('0:1');

      expect(t.flashes.isLit('0:1'), isTrue);
    });

    test('se apaga solo cuando pasa su tiempo', () {
      final t = build();
      t.flashes.fire('0:1');

      t.advance(101);

      expect(t.flashes.isLit('0:1'), isFalse);
    });

    test('un pad que no ha sonado nunca está apagado', () {
      final t = build();

      expect(t.flashes.isLit('3:15'), isFalse);
    });

    test('volver a golpear reinicia el destello en vez de apilarlo', () {
      final t = build();
      t.flashes.fire('0:1');
      t.advance(80);

      t.flashes.fire('0:1');
      t.advance(80);

      expect(t.flashes.isLit('0:1'), isTrue);
    });

    test('cada pad se apaga por su cuenta', () {
      final t = build();
      t.flashes.fire('0:1');
      t.advance(60);
      t.flashes.fire('0:2');

      t.advance(50);

      expect(t.flashes.isLit('0:1'), isFalse);
      expect(t.flashes.isLit('0:2'), isTrue);
    });
  });

  group('si hay que seguir repintando', () {
    test('con algo encendido, sí', () {
      final t = build();
      t.flashes.fire('0:1');

      expect(t.flashes.any, isTrue);
    });

    test('cuando se apaga el último, no', () {
      final t = build();
      t.flashes.fire('0:1');

      t.advance(101);

      expect(t.flashes.any, isFalse);
    });

    test('preguntar barre lo apagado y no deja basura detrás', () {
      final t = build();
      for (var i = 0; i < 50; i++) {
        t.flashes.fire('0:$i');
      }

      t.advance(101);

      expect(t.flashes.any, isFalse);
      expect(t.flashes.isLit('0:0'), isFalse);
    });

    test('parar del todo apaga la rejilla entera', () {
      final t = build();
      t.flashes.fire('0:1');

      t.flashes.clear();

      expect(t.flashes.any, isFalse);
    });
  });
}
