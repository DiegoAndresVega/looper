import 'package:flutter_test/flutter_test.dart';
import 'package:looper/core/constants.dart';
import 'package:looper/domain/pattern.dart';
import 'package:looper/domain/song.dart';
import 'package:looper/state/sequencer.dart';

/// A sequencer whose sixteen patterns each carry one note naming themselves,
/// so what comes out says which pattern it came from.
({Sequencer seq, List<Set<String>> fired}) build() {
  final fired = <Set<String>>[];
  final seq = Sequencer(
    onNotes: (play) => fired.add(play.notes),
    onPatternsChanged: () {},
  );
  seq.load(
    [
      for (var i = 0; i < kPatternCount; i++)
        Pattern.empty().withNote(0, 'P$i'),
    ],
    0,
  );
  return (seq: seq, fired: fired);
}

/// One whole bar of sixteenths.
void playBar(Sequencer seq) {
  for (var i = 0; i < kPatternSteps; i++) {
    seq.tick();
  }
}

/// Which patterns sounded, in order, on the downbeats.
List<String> heard(List<Set<String>> fired) =>
    fired.where((s) => s.isNotEmpty).map((s) => s.first).toList();

void main() {
  final song = const Song.empty()
      .appended(const SongStep(pattern: 0, repeats: 2))
      .appended(const SongStep(pattern: 3))
      .appended(const SongStep(pattern: 1));

  group('la canción manda sobre el orden', () {
    test('cada compás trae el patrón que la canción dice', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.togglePlay();

      for (var bar = 0; bar < 4; bar++) {
        playBar(t.seq);
      }

      expect(heard(t.fired), ['P0', 'P0', 'P3', 'P1']);
    });

    test('al acabar vuelve al principio', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.togglePlay();

      for (var bar = 0; bar < 5; bar++) {
        playBar(t.seq);
      }

      expect(heard(t.fired).last, 'P0');
      expect(t.seq.songBar, 4);
    });

    test('arranca por el primero aunque la rejilla mostrara otro', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.selectPattern(7);

      t.seq.togglePlay();
      playBar(t.seq);

      expect(heard(t.fired), ['P0']);
      expect(t.seq.patternIndex, 0);
    });

    test('la canción gana a la cadena', () {
      final t = build();
      t.seq.chainLength = 8;
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.togglePlay();

      playBar(t.seq);
      playBar(t.seq);
      playBar(t.seq);

      expect(heard(t.fired), ['P0', 'P0', 'P3']);
    });

    test('una canción vacía deja mandar a la cadena', () {
      final t = build();
      t.seq.songMode = true;
      t.seq.chainLength = 2;
      t.seq.togglePlay();

      playBar(t.seq);
      playBar(t.seq);

      expect(heard(t.fired), ['P0', 'P1']);
    });

    test('apagar el modo canción devuelve el mando a la cadena', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.chainLength = 2;
      t.seq.songMode = false;
      t.seq.togglePlay();

      playBar(t.seq);
      playBar(t.seq);

      expect(heard(t.fired), ['P0', 'P1']);
    });
  });

  group('el compás que suena', () {
    test('la canción dice en qué entrada va', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.togglePlay();

      playBar(t.seq);
      playBar(t.seq);
      playBar(t.seq);

      expect(t.seq.songBar, 2);
      expect(song.indexForBar(t.seq.songBar), 1);
    });

    test('parar devuelve la canción a su primer compás', () {
      final t = build();
      t.seq.setSong(song);
      t.seq.songMode = true;
      t.seq.togglePlay();
      playBar(t.seq);
      playBar(t.seq);

      t.seq.togglePlay();

      expect(t.seq.songBar, 0);
    });
  });

  group('cruzar la línea de compás', () {
    test('un paso adelantado del compás siguiente sale antes de tiempo', () {
      final t = build();
      // El primer paso del patrón 3 va medio paso por delante: tiene que
      // salir en el último tick del compás anterior, no en el suyo.
      t.seq.load(
        [
          for (var i = 0; i < kPatternCount; i++)
            Pattern.empty().withNote(0, 'P$i').withNudge(0, -0.5),
        ],
        0,
      );
      t.seq.setSong(
        const Song.empty()
            .appended(const SongStep(pattern: 0))
            .appended(const SongStep(pattern: 3)),
      );
      t.seq.songMode = true;
      t.seq.togglePlay();

      playBar(t.seq);

      // El último tick del primer compás ya lleva el golpe del patrón 3.
      expect(t.fired.last.first, 'P3');
    });

    test('lo adelantado no vuelve a sonar en su propio tick', () {
      final t = build();
      t.seq.load(
        [
          for (var i = 0; i < kPatternCount; i++)
            Pattern.empty().withNote(0, 'P$i').withNudge(0, -0.5),
        ],
        0,
      );
      t.seq.setSong(
        const Song.empty()
            .appended(const SongStep(pattern: 0))
            .appended(const SongStep(pattern: 3)),
      );
      t.seq.songMode = true;
      t.seq.togglePlay();

      playBar(t.seq);
      t.seq.tick();

      expect(heard(t.fired).where((p) => p == 'P3').length, 1);
    });
  });
}
