import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/mixer_tap.dart';

/// El motor solo entrega **un** flujo de la salida del mezclador a la vez, así
/// que exportar la sesión y rescatar lo que acaba de sonar no pueden abrir cada
/// uno el suyo. Todo pasa por un único grifo que reparte.
///
/// Lo que se prueba aquí es la parte que no necesita motor: el anillo que
/// siempre guarda los últimos segundos, y la conversión de lo que sale del
/// mezclador —PCM entrelazado de 16 bits— a las muestras que la app usa.
void main() {
  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  group('el anillo de los últimos segundos', () {
    test('nace vacío', () {
      expect(RingBuffer(capacity: 8).read(), isEmpty);
    });

    test('devuelve lo escrito mientras quepa', () {
      final ring = RingBuffer(capacity: 8)..write(bytes([1, 2, 3]));

      expect(ring.read(), [1, 2, 3]);
    });

    test('al llenarse conserva lo último, no lo primero', () {
      // Es la regla que define un skip-back: lo que acabas de tocar es lo que
      // interesa, lo de hace un minuto ya no.
      final ring = RingBuffer(capacity: 4)
        ..write(bytes([1, 2, 3]))
        ..write(bytes([4, 5, 6]));

      expect(ring.read(), [3, 4, 5, 6]);
    });

    test('mantiene el orden al dar la vuelta varias veces', () {
      final ring = RingBuffer(capacity: 5);
      for (var i = 1; i <= 12; i++) {
        ring.write(bytes([i]));
      }

      expect(ring.read(), [8, 9, 10, 11, 12]);
    });

    test('una escritura más larga que el anillo deja solo su cola', () {
      final ring = RingBuffer(capacity: 3)..write(bytes([1, 2, 3, 4, 5, 6, 7]));

      expect(ring.read(), [5, 6, 7]);
    });

    test('vaciarlo lo deja como recién hecho', () {
      final ring = RingBuffer(capacity: 4)
        ..write(bytes([1, 2, 3]))
        ..clear();

      expect(ring.read(), isEmpty);
      expect(ring.length, 0);
    });

    test('escribir nada no cambia nada', () {
      final ring = RingBuffer(capacity: 4)
        ..write(bytes([1, 2]))
        ..write(Uint8List(0));

      expect(ring.read(), [1, 2]);
    });

    test('dice cuánto lleva guardado sin pasarse de su tamaño', () {
      final ring = RingBuffer(capacity: 4);

      ring.write(bytes([1, 2]));
      expect(ring.length, 2);

      ring.write(bytes([3, 4, 5, 6]));
      expect(ring.length, 4);
    });

    test('leer no vacía: el anillo sigue corriendo detrás', () {
      final ring = RingBuffer(capacity: 4)..write(bytes([1, 2, 3]));

      ring.read();

      expect(ring.read(), [1, 2, 3]);
    });
  });

  group('de la salida del mezclador a muestras', () {
    /// Un entero de 16 bits con signo, en little endian, como lo entrega el
    /// mezclador.
    Uint8List pcm16(List<int> values) {
      final out = ByteData(values.length * 2);
      for (var i = 0; i < values.length; i++) {
        out.setInt16(i * 2, values[i], Endian.little);
      }
      return out.buffer.asUint8List();
    }

    test('el silencio sale en silencio', () {
      final muestras = samplesFromPcm16(pcm16([0, 0, 0, 0]), channels: 1);

      expect(muestras, [0.0, 0.0, 0.0, 0.0]);
    });

    test('el tope positivo llega casi a uno', () {
      final muestras = samplesFromPcm16(pcm16([32767]), channels: 1);

      expect(muestras.first, closeTo(1.0, 0.001));
    });

    test('el tope negativo llega a menos uno', () {
      final muestras = samplesFromPcm16(pcm16([-32768]), channels: 1);

      expect(muestras.first, closeTo(-1.0, 0.001));
    });

    test('el estéreo se promedia a mono, que es como toca la app', () {
      // Izquierda a tope, derecha en silencio: el centro queda a la mitad.
      final muestras = samplesFromPcm16(pcm16([32767, 0]), channels: 2);

      expect(muestras.length, 1);
      expect(muestras.first, closeTo(0.5, 0.001));
    });

    test('un byte suelto al final no rompe la conversión', () {
      // Los trozos del flujo no vienen alineados a la muestra.
      final crudo = Uint8List.fromList([...pcm16([100, 200]), 7]);

      expect(samplesFromPcm16(crudo, channels: 1).length, 2);
    });

    test('un trozo incompleto de estéreo se descarta entero', () {
      final crudo = pcm16([32767, 0, 32767]); // falta el canal derecho

      expect(samplesFromPcm16(crudo, channels: 2).length, 1);
    });

    test('nada entra, nada sale', () {
      expect(samplesFromPcm16(Uint8List(0), channels: 2), isEmpty);
    });
  });

  group('leer la cabecera que da el motor', () {
    Uint8List header({required int channels, required int sampleRate}) {
      final h = ByteData(44);
      h.setUint16(22, channels, Endian.little);
      h.setUint32(24, sampleRate, Endian.little);
      return h.buffer.asUint8List();
    }

    test('saca canales y frecuencia en vez de darlos por supuestos', () {
      final formato = formatFromHeader(header(channels: 2, sampleRate: 48000));

      expect(formato.channels, 2);
      expect(formato.sampleRate, 48000);
    });

    test('una cabecera corta cae en el formato de la app', () {
      final formato = formatFromHeader(Uint8List(10));

      expect(formato.channels, 1);
      expect(formato.sampleRate, 44100);
    });

    test('valores imposibles no se creen', () {
      final formato = formatFromHeader(header(channels: 0, sampleRate: 0));

      expect(formato.channels, greaterThan(0));
      expect(formato.sampleRate, greaterThan(0));
    });
  });
}
