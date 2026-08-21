/// Cutting one sound into pieces and spreading them across the grid.
///
/// Nothing here copies audio. [Sound] already carries non-destructive trim
/// points, so sixteen chops are sixteen sounds pointing at the same file with
/// different `trimStartMs`/`trimEndMs`. That is what makes chopping a 60second
/// import cost nothing on disk — and it is also why [isFileOrphaned] exists:
/// once several sounds share a file, deleting one of them can no longer take
/// the file with it.
library;

import 'dart:typed_data';

import '../core/constants.dart';
import '../domain/session.dart';
import '../domain/sound.dart';

/// One piece, in milliseconds from the start of the file.
typedef Slice = ({int startMs, int endMs});

/// How to decide where the cuts go. Transients follow the audio; the fixed
/// divisions follow the bar, which is what a loop already recorded in time
/// wants.
enum ChopMode {
  transients('Transitorios', 0),
  eight('En 8', 8),
  sixteen('En 16', kPadsPerBank);

  const ChopMode(this.label, this.pieces);

  final String label;
  final int pieces;
}

/// Cuts [durationMs] into [count] equal pieces.
///
/// Boundaries are computed from the ends rather than accumulated, so rounding
/// cannot drift: the pieces always run edge to edge and the last one reaches
/// the end of the audio instead of stopping a few milliseconds short.
List<Slice> sliceEvenly({required int durationMs, required int count}) {
  final pieces = count.clamp(1, durationMs.clamp(1, durationMs));
  final slices = <Slice>[];
  for (var i = 0; i < pieces; i++) {
    final start = durationMs * i ~/ pieces;
    final end = i == pieces - 1 ? durationMs : durationMs * (i + 1) ~/ pieces;
    if (end > start) slices.add((startMs: start, endMs: end));
  }
  return slices;
}

/// Where the hits are in a peak envelope, as bucket indices.
///
/// A plain onset detector: energy that rises sharply from one bucket to the
/// next is a hit. Rises are ranked by how big they are, the strongest kept,
/// and [minGap] stops one drum being read as three. Index 0 is always
/// included — whatever comes before the first hit is a piece too.
List<int> detectOnsets(
  Float32List envelope, {
  required int maxOnsets,
  int minGap = 3,
  double threshold = 0.12,
}) {
  if (envelope.isEmpty) return const [];
  if (maxOnsets <= 1) return const [0];

  var loudest = 0.0;
  for (final v in envelope) {
    if (v > loudest) loudest = v;
  }
  if (loudest <= 0) return const [0];

  // Rising energy only: a decay is the tail of a hit, not a new one.
  final rises = <({int at, double strength})>[];
  for (var i = 1; i < envelope.length; i++) {
    final rise = (envelope[i] - envelope[i - 1]) / loudest;
    if (rise >= threshold) rises.add((at: i, strength: rise));
  }
  rises.sort((a, b) => b.strength.compareTo(a.strength));

  final picked = <int>[0];
  for (final rise in rises) {
    if (picked.length >= maxOnsets) break;
    final tooClose = picked.any((at) => (at - rise.at).abs() < minGap);
    if (tooClose) continue;
    picked.add(rise.at);
  }

  picked.sort();
  return picked;
}

/// Turns bucket indices into pieces: each hit runs until the next one, and the
/// last runs to the end of the audio.
List<Slice> slicesFromOnsets({
  required List<int> onsets,
  required int buckets,
  required int durationMs,
}) {
  if (onsets.isEmpty || buckets <= 0) {
    return sliceEvenly(durationMs: durationMs, count: 1);
  }

  int msAt(int bucket) => (durationMs * bucket / buckets).round();

  final slices = <Slice>[];
  for (var i = 0; i < onsets.length; i++) {
    final start = msAt(onsets[i]);
    final end = i == onsets.length - 1 ? durationMs : msAt(onsets[i + 1]);
    if (end > start) slices.add((startMs: start, endMs: end));
  }
  return slices;
}

/// Builds one sound per piece, all sharing [source]'s file.
///
/// [slices] are offsets inside what the source actually plays, so chopping an
/// already-trimmed sound stays inside that trim: what you see in the waveform
/// is what gets cut.
List<Sound> chopSound({
  required Sound source,
  required List<Slice> slices,
  required String Function(int index) idFor,
}) {
  final origin = source.trimStartMs;
  return [
    for (var i = 0; i < slices.length; i++)
      Sound(
        id: idFor(i),
        name: '${source.name} ${i + 1}',
        family: source.family,
        fileName: source.fileName,
        // Always yours, whatever it was cut from. Inheriting the origin made
        // chops of a factory sound undeletable and filed them under «Kit»,
        // which is not where something you made an hour ago belongs.
        origin: SoundOrigin.recorded,
        durationMs: source.durationMs,
        sizeBytes: source.sizeBytes,
        trimStartMs: origin + slices[i].startMs,
        trimEndMs: origin + slices[i].endMs,
        volume: source.volume,
        semitones: source.semitones,
      ),
  ];
}

/// Whether [fileName] is safe to delete: true only when nothing left in the
/// library still points at it. Chops share a file, so deleting one of them
/// must not pull the audio out from under its siblings.
bool isFileOrphaned(String fileName, Iterable<Sound> remaining) =>
    !remaining.any((s) => s.fileName == fileName);

/// Where a run of [count] chops can land: the first bank holding that many
/// free pads in a row, searched C, D, A, B — the same order a single recording
/// takes, so what you make lands where your own things live and the factory
/// kit is the last thing to be built over.
///
/// A run, not scattered gaps: chops are only readable when pad order matches
/// the order of the audio.
({int bank, int slot})? findRoomFor(Session session, int count) {
  if (count <= 0) return null;
  for (final bank in const [2, 3, 0, 1]) {
    final pads = session.banks[bank].pads;
    var run = 0;
    for (var slot = 0; slot < pads.length; slot++) {
      run = pads[slot].isEmpty ? run + 1 : 0;
      if (run == count) return (bank: bank, slot: slot - count + 1);
    }
  }
  return null;
}
