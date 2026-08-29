import 'package:flutter_test/flutter_test.dart';
import 'package:looper/ui/pads/sequencer_bar.dart';

/// La pastilla de la cadena es un anillo: 1, 2, 4, 8, 16 y vuelta a empezar.
/// Con una canción escrita gana una posición más al final, porque la cadena y
/// la canción responden a la misma pregunta —qué suena después de este compás—
/// y dos mandos para una pregunta acaban contradiciéndose.
void main() {
  group('el anillo de la cadena', () {
    test('cada toque sube a la siguiente longitud musical', () {
      expect(
        nextChainStop(chainLength: 1, songMode: false, hasSong: false).bars,
        2,
      );
      expect(
        nextChainStop(chainLength: 4, songMode: false, hasSong: false).bars,
        8,
      );
    });

    test('sin canción, del último vuelve al primero', () {
      final next =
          nextChainStop(chainLength: 16, songMode: false, hasSong: false);

      expect(next.bars, 1);
      expect(next.song, isFalse);
    });

    test('una longitud rara vuelve al principio del anillo', () {
      expect(
        nextChainStop(chainLength: 7, songMode: false, hasSong: false).bars,
        1,
      );
    });
  });

  group('la canción, una posición más', () {
    test('con canción escrita, después del último compás manda ella', () {
      final next =
          nextChainStop(chainLength: 16, songMode: false, hasSong: true);

      expect(next.song, isTrue);
    });

    test('la canción no se ofrece si no está escrita', () {
      expect(
        nextChainStop(chainLength: 16, songMode: false, hasSong: false).song,
        isFalse,
      );
    });

    test('saliendo de la canción se vuelve a un compás', () {
      final next =
          nextChainStop(chainLength: 16, songMode: true, hasSong: true);

      expect(next.song, isFalse);
      expect(next.bars, 1);
    });
  });
}
