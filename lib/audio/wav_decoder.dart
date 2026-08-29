import 'dart:typed_data';

import '../core/constants.dart';

/// Thrown when a file that claims to be a WAV cannot be read. The recorder
/// writes these files, but an imported one can be anything at all.
class WavFormatException implements Exception {
  const WavFormatException(this.message);

  final String message;

  @override
  String toString() => 'WavFormatException: $message';
}

/// A decoded WAV, always mono: a stereo file is averaged down on the way in
/// because the instrument plays and edits single-channel sounds.
class DecodedWav {
  const DecodedWav({
    required this.samples,
    required this.sampleRate,
    required this.channels,
  });

  final Float32List samples;
  final int sampleRate;

  /// Channel count of the source file, kept for display only.
  final int channels;

  int get durationMs => (samples.length / sampleRate * 1000).round();
}

const int _headerMinBytes = 44;
const int _formatPcm = 1;
const int _formatFloat = 3;
const int _formatExtensible = 0xFFFE;

/// Reads a RIFF/WAVE file into mono float samples in the -1..1 range.
/// Supports 16-bit PCM (what the app writes) and 32-bit float (what the
/// capture device hands over). Anything else is rejected by name.
DecodedWav decodeWav(Uint8List bytes) {
  if (bytes.length < _headerMinBytes) {
    throw const WavFormatException('el archivo es demasiado corto');
  }

  final data = ByteData.sublistView(bytes);
  if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
    throw const WavFormatException('no es un archivo WAV');
  }

  int? format;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;

  // Chunks are walked rather than assumed: recorders slip LIST and fact
  // chunks in before the audio.
  var cursor = 12;
  while (cursor + 8 <= bytes.length) {
    final id = _tag(bytes, cursor);
    final size = data.getUint32(cursor + 4, Endian.little);
    final body = cursor + 8;

    if (id == 'fmt ' && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      dataOffset = body;
      // A file cut short mid-write still plays back what did land on disk.
      dataLength = size == 0 || body + size > bytes.length
          ? bytes.length - body
          : size;
      break;
    }

    cursor = body + size + (size.isOdd ? 1 : 0);
  }

  if (format == null || channels == null || sampleRate == null ||
      bitsPerSample == null) {
    throw const WavFormatException('falta la cabecera de formato');
  }
  if (dataOffset == null || dataLength == null || dataLength <= 0) {
    throw const WavFormatException('el archivo no trae audio');
  }
  if (channels < 1 || sampleRate < 1) {
    throw const WavFormatException('cabecera con valores imposibles');
  }

  final isFloat = format == _formatFloat ||
      (format == _formatExtensible && bitsPerSample == 32);
  if (!isFloat && format != _formatPcm) {
    throw WavFormatException('formato $format no soportado');
  }
  if (!(bitsPerSample == 16 || (isFloat && bitsPerSample == 32))) {
    throw WavFormatException('$bitsPerSample bits no soportados');
  }

  final interleaved = isFloat
      ? _readFloat32(data, dataOffset, dataLength)
      : _readInt16(data, dataOffset, dataLength);

  return DecodedWav(
    samples: channels == 1 ? interleaved : _toMono(interleaved, channels),
    sampleRate: sampleRate,
    channels: channels,
  );
}

String _tag(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes, offset, offset + 4);

Float32List _readInt16(ByteData data, int offset, int length) {
  final count = length ~/ 2;
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = data.getInt16(offset + i * 2, Endian.little) / 32767.0;
  }
  return out;
}

Float32List _readFloat32(ByteData data, int offset, int length) {
  final count = length ~/ 4;
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = data.getFloat32(offset + i * 4, Endian.little);
  }
  return out;
}

Float32List _toMono(Float32List interleaved, int channels) {
  final frames = interleaved.length ~/ channels;
  final out = Float32List(frames);
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += interleaved[frame * channels + c];
    }
    out[frame] = sum / channels;
  }
  return out;
}

/// Peak per bucket, ready to paint as a waveform. Always returns [buckets]
/// values so the drawing code never has to special-case an empty take.
Float32List peakEnvelope(Float32List samples, int buckets) {
  final out = Float32List(buckets);
  if (samples.isEmpty || buckets <= 0) return out;

  final perBucket = samples.length / buckets;
  for (var i = 0; i < buckets; i++) {
    final start = (i * perBucket).floor();
    final end = ((i + 1) * perBucket).ceil().clamp(start + 1, samples.length);
    var peak = 0.0;
    for (var s = start; s < end && s < samples.length; s++) {
      final value = samples[s].abs();
      if (value > peak) peak = value;
    }
    out[i] = peak > 1.0 ? 1.0 : peak;
  }
  return out;
}

/// Lifts a quiet take up to [peak] so a recording sits at the same level as
/// the factory kit. Silence is left alone instead of amplifying its noise.
/// The same audio, back to front. A new buffer: the caller's samples are
/// very often the ones a waveform is being drawn from.
Float32List reversedSamples(Float32List samples) {
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[samples.length - 1 - i];
  }
  return out;
}

Float32List normalized(Float32List samples, {double peak = 0.9}) {
  var loudest = 0.0;
  for (final sample in samples) {
    final value = sample.abs();
    if (value > loudest) loudest = value;
  }
  if (loudest == 0.0) return Float32List.fromList(samples);

  final gain = peak / loudest;
  final out = Float32List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = samples[i] * gain;
  }
  return out;
}

/// Hard ceiling on how long a recorded sound can be. Anything past ten
/// seconds is dropped rather than rejected, so a late stop still saves.
Float32List capToMaxDuration(Float32List samples, {required int sampleRate}) {
  final limit = sampleRate * kMaxRecordDuration.inSeconds;
  if (samples.length <= limit) return samples;
  return Float32List.sublistView(samples, 0, limit);
}
