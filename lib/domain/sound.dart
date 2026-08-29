import 'dart:math' as math;

import '../core/palette.dart';

/// Where a sound came from. Shown as a label in the library, never as a folder.
enum SoundOrigin {
  factory_('Kit'),
  recorded('Mío'),
  imported('Importado');

  const SoundOrigin(this.label);

  final String label;
}

/// A sound file living on the device, plus the non-destructive edits applied
/// to it. Trimming, pitch and reverse never touch the underlying file.
class Sound {
  const Sound({
    required this.id,
    required this.name,
    required this.family,
    required this.fileName,
    required this.origin,
    required this.durationMs,
    required this.sizeBytes,
    this.trimStartMs = 0,
    this.trimEndMs,
    this.volume = 1.0,
    this.semitones = 0,
    this.reversed = false,
  });

  final String id;
  final String name;
  final SoundFamily family;
  final String fileName;
  final SoundOrigin origin;
  final int durationMs;
  final int sizeBytes;

  /// Non-destructive edits.
  final int trimStartMs;
  final int? trimEndMs;
  final double volume;
  final int semitones;
  /// True when the file on disk is already back to front. Reversing writes a
  /// new file rather than a flag the engine has to honour — a chop's pieces
  /// share one file, and a flag would have turned all sixteen of them around
  /// at once.
  final bool reversed;

  int get effectiveEndMs => trimEndMs ?? durationMs;
  int get trimmedDurationMs => (effectiveEndMs - trimStartMs).clamp(1, durationMs);

  /// Tape-style playback rate: pitch and speed move together.
  double get playbackRate =>
      semitones == 0 ? 1.0 : math.pow(2, semitones / 12.0).toDouble();

  Sound copyWith({
    String? name,
    SoundFamily? family,
    int? trimStartMs,
    int? trimEndMs,
    double? volume,
    int? semitones,
    bool? reversed,
  }) {
    return Sound(
      id: id,
      name: name ?? this.name,
      family: family ?? this.family,
      fileName: fileName,
      origin: origin,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      volume: volume ?? this.volume,
      semitones: semitones ?? this.semitones,
      reversed: reversed ?? this.reversed,
    );
  }

  /// The same sound pointed at a new file of the same length: a rendering
  /// that changed the audio without changing how long it lasts, like a real
  /// transposition. The trim is untouched, because the window it describes
  /// has not moved.
  Sound rewrittenOnto({required String fileName, required int sizeBytes}) =>
      Sound(
        id: id,
        name: name,
        family: family,
        fileName: fileName,
        origin: origin,
        durationMs: durationMs,
        sizeBytes: sizeBytes,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
        volume: volume,
        semitones: semitones,
        reversed: reversed,
      );

  /// And one pointed at a file of a different length. The trim scales with
  /// it: a sound stretched to half the tempo keeps the same *musical* window,
  /// not the same number of milliseconds.
  Sound stretchedOnto({
    required String fileName,
    required int sizeBytes,
    required int durationMs,
  }) {
    final ratio = this.durationMs == 0 ? 1.0 : durationMs / this.durationMs;
    return Sound(
      id: id,
      name: name,
      family: family,
      fileName: fileName,
      origin: origin,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      trimStartMs: (trimStartMs * ratio).round(),
      trimEndMs: trimEndMs == null ? null : (trimEndMs! * ratio).round(),
      volume: volume,
      semitones: semitones,
      reversed: reversed,
    );
  }

  /// The same sound pointed at its reversed file: same identity, same volume
  /// and pitch, and the trim seen from the other end.
  ///
  /// Reflecting the trim is the whole point. A window from 0.2 s to 0.8 s of
  /// a one-second sound is, read backwards, the window from 0.2 s to 0.8 s;
  /// one that ended at 0.3 s becomes one that starts at 0.7 s. Without this
  /// the file turns around and the audible part does not, so reversing a
  /// trimmed sound would play a different piece of it.
  Sound reversedOnto({required String fileName, required int sizeBytes}) {
    final start = durationMs - effectiveEndMs;
    final end = durationMs - trimStartMs;
    return Sound(
      id: id,
      name: name,
      family: family,
      fileName: fileName,
      origin: origin,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
      // A sound with no trim at all keeps none: null means «to the end», and
      // writing the length in would freeze it.
      trimStartMs: trimEndMs == null ? 0 : start,
      trimEndMs: trimStartMs == 0 && trimEndMs == null ? null : end,
      volume: volume,
      semitones: semitones,
      reversed: !reversed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'family': family.name,
        'fileName': fileName,
        'origin': origin.name,
        'durationMs': durationMs,
        'sizeBytes': sizeBytes,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'volume': volume,
        'semitones': semitones,
        'reversed': reversed,
      };

  factory Sound.fromJson(Map<String, dynamic> json) {
    return Sound(
      id: json['id'] as String,
      name: json['name'] as String,
      family: SoundFamily.values.byName(json['family'] as String),
      fileName: json['fileName'] as String,
      origin: SoundOrigin.values.byName(json['origin'] as String),
      durationMs: json['durationMs'] as int,
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      trimStartMs: json['trimStartMs'] as int? ?? 0,
      trimEndMs: json['trimEndMs'] as int?,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      semitones: json['semitones'] as int? ?? 0,
      // 'fadeMs' was written by every version up to this one and read by
      // none. It is not read here either: a field the app has never honoured
      // is not data, and carrying it forward would keep promising a fade
      // that does not exist.
      reversed: json['reversed'] as bool? ?? false,
    );
  }
}
