import 'dart:typed_data';

/// Encodes mono float samples as a 16-bit PCM WAV file.
/// Used for the generated factory kit and for exporting a take.
Uint8List encodeWav(
  Float32List samples, {
  required int sampleRate,
  int channels = 1,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final dataBytes = samples.length * 2;

  final bytes = BytesBuilder();
  final header = ByteData(44);

  void ascii(int offset, String tag) {
    for (var i = 0; i < tag.length; i++) {
      header.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // format: PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);

  bytes.add(header.buffer.asUint8List());

  final pcm = ByteData(dataBytes);
  for (var i = 0; i < samples.length; i++) {
    final clamped = samples[i].clamp(-1.0, 1.0);
    pcm.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  bytes.add(pcm.buffer.asUint8List());

  return bytes.toBytes();
}
