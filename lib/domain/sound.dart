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
    this.fadeMs = 0,
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
  final bool reversed;
  final int fadeMs;

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
    int? fadeMs,
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
      fadeMs: fadeMs ?? this.fadeMs,
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
        'fadeMs': fadeMs,
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
      reversed: json['reversed'] as bool? ?? false,
      fadeMs: json['fadeMs'] as int? ?? 0,
    );
  }
}
