import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pad_config.dart';

void main() {
  group('qué le hace un golpe al anterior', () {
    test('en corte, el golpe nuevo mata al que sonaba', () {
      expect(
        hitActionFor(mode: PadPlayMode.cut, isSounding: true),
        HitAction.cutPrevious,
      );
    });

    test('en corte sin nada sonando, simplemente suena', () {
      expect(
        hitActionFor(mode: PadPlayMode.cut, isSounding: false),
        HitAction.cutPrevious,
      );
    });

    test('en capas se apilan', () {
      expect(
        hitActionFor(mode: PadPlayMode.layer, isSounding: true),
        HitAction.layer,
      );
    });

    test('una vez: mientras suena, el golpe se descarta', () {
      expect(
        hitActionFor(mode: PadPlayMode.once, isSounding: true),
        HitAction.ignore,
      );
    });

    test('una vez: acabado, vuelve a poder dispararse', () {
      expect(
        hitActionFor(mode: PadPlayMode.once, isSounding: false),
        HitAction.layer,
      );
    });
  });

  group('grupos de corte', () {
    test('sin grupo no corta a nadie', () {
      final victims = chokeVictims(
        firingKey: '0:0',
        group: kNoChokeGroup,
        sounding: {'0:1': 1, '0:2': 1},
      );

      expect(victims, isEmpty);
    });

    test('corta a los de su grupo y a nadie más', () {
      final victims = chokeVictims(
        firingKey: '0:0',
        group: 1,
        sounding: {'0:1': 1, '0:2': 2, '0:3': kNoChokeGroup, '0:4': 1},
      );

      expect(victims, {'0:1', '0:4'});
    });

    test('no se corta a sí mismo: de eso ya se encarga el modo', () {
      final victims = chokeVictims(
        firingKey: '0:0',
        group: 1,
        sounding: {'0:0': 1, '0:1': 1},
      );

      expect(victims, {'0:1'});
    });

    test('el charles cerrado calla al abierto, y el abierto al cerrado', () {
      // La convención del MPC: un solo charles físico, una sola voz.
      const abierto = '0:2';
      const cerrado = '0:3';

      expect(
        chokeVictims(firingKey: cerrado, group: 1, sounding: {abierto: 1}),
        {abierto},
      );
      expect(
        chokeVictims(firingKey: abierto, group: 1, sounding: {cerrado: 1}),
        {cerrado},
      );
    });
  });

  group('el pad guarda las dos cosas', () {
    test('por defecto, corte y sin grupo', () {
      const pad = PadConfig(soundId: 's');

      expect(pad.playMode, PadPlayMode.cut);
      expect(pad.chokeGroup, kNoChokeGroup);
    });

    test('el grupo se recorta al rango', () {
      expect(const PadConfig(chokeGroup: -2).chokeGroup, kNoChokeGroup);
      expect(const PadConfig(chokeGroup: 99).chokeGroup, kChokeGroups);
    });

    test('los dos viajan al disco y vuelven', () {
      const pad = PadConfig(
        soundId: 's',
        playMode: PadPlayMode.once,
        chokeGroup: 2,
      );

      final back = PadConfig.fromJson(pad.toJson());

      expect(back.playMode, PadPlayMode.once);
      expect(back.chokeGroup, 2);
    });

    test('un pad de antes de los modos abre en corte y sin grupo', () {
      final back = PadConfig.fromJson(const {
        'soundId': 's',
        'volume': 0.8,
        'semitones': 0,
      });

      expect(back.playMode, PadPlayMode.cut);
      expect(back.chokeGroup, kNoChokeGroup);
    });

    test('un modo desconocido en el fichero no rompe el pad', () {
      final back = PadConfig.fromJson(const {
        'soundId': 's',
        'playMode': 'loquesea',
      });

      expect(back.playMode, PadPlayMode.cut);
    });
  });
}
