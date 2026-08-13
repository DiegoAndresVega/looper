import 'package:flutter_test/flutter_test.dart';
import 'package:looper/audio/fx_curves.dart';

/// Twenty-one posiciones del mando, de tope a tope.
final List<double> _throw =
    List.generate(21, (i) => i / 20).map((v) => v.toDouble()).toList();

void main() {
  group('dentro de lo que el plugin acepta', () {
    // Este grupo es el fallo original: un valor fuera de rango no se recorta,
    // se descarta con un aviso en el log. El mando se movía y no pasaba nada,
    // o el filtro se quedaba con su ajuste de fábrica.
    test('el corte del filtro nunca se sale', () {
      for (final knob in _throw) {
        final hz = filterCutoffHz(knob);
        expect(hz, inInclusiveRange(kBiquadMinHz, kBiquadMaxHz),
            reason: 'el mando en $knob pedía $hz Hz');
      }
    });

    test('la resonancia nunca se sale', () {
      for (final knob in _throw) {
        expect(filterResonance(knob),
            inInclusiveRange(kBiquadMinResonance, kBiquadMaxResonance));
      }
    });

    test('el drive nunca se sale, ni en frecuencia ni en bits', () {
      for (final knob in _throw) {
        expect(crushRateHz(knob), inInclusiveRange(kCrushMinHz, kCrushMaxHz),
            reason: 'el mando en $knob pedía ${crushRateHz(knob)} Hz');
        expect(crushBitdepth(knob),
            inInclusiveRange(kCrushMinBitdepth, kCrushMaxBitdepth));
      }
    });

    test('un mando fuera de sitio se recoge en vez de colarse', () {
      expect(filterCutoffHz(2), inInclusiveRange(kBiquadMinHz, kBiquadMaxHz));
      expect(filterCutoffHz(-1), inInclusiveRange(kBiquadMinHz, kBiquadMaxHz));
      expect(crushRateHz(2), inInclusiveRange(kCrushMinHz, kCrushMaxHz));
      expect(crushBitdepth(-1),
          inInclusiveRange(kCrushMinBitdepth, kCrushMaxBitdepth));
    });
  });

  group('el filtro se comporta como un filtro', () {
    test('arriba está abierto y abajo cierra', () {
      expect(filterCutoffHz(1), kBiquadMaxHz);
      expect(filterCutoffHz(0), lessThan(300));
    });

    test('subir el mando sube el corte, sin escalones al revés', () {
      var previous = 0.0;
      for (final knob in _throw) {
        final hz = filterCutoffHz(knob);
        expect(hz, greaterThan(previous), reason: 'se echó atrás en $knob');
        previous = hz;
      }
    });

    test('la mitad del mando es la mitad de las octavas, no de los hercios', () {
      final low = filterCutoffHz(0);
      final mid = filterCutoffHz(0.5);
      final high = filterCutoffHz(1);

      expect(mid / low, closeTo(high / mid, 0.01));
    });

    test('sin resonancia el filtro no repica', () {
      expect(filterResonance(0), 1);
      expect(filterResonance(1), greaterThan(10));
    });
  });

  group('el drive se comporta como un triturador', () {
    test('en reposo es transparente y al tope es grava', () {
      expect(crushRateHz(0), kCrushMaxHz);
      expect(crushBitdepth(0), kCrushMaxBitdepth);
      expect(crushRateHz(1), lessThan(5000));
      expect(crushBitdepth(1), lessThanOrEqualTo(4));
    });

    test('subir el mando destruye más, nunca menos', () {
      var previousHz = double.infinity;
      var previousBits = double.infinity;
      for (final knob in _throw) {
        expect(crushRateHz(knob), lessThan(previousHz));
        expect(crushBitdepth(knob), lessThan(previousBits));
        previousHz = crushRateHz(knob);
        previousBits = crushBitdepth(knob);
      }
    });
  });
}
