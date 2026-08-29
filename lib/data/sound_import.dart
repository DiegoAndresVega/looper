import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../audio/wav_decoder.dart';
import '../audio/wav_encoder.dart';
import '../core/constants.dart';
import '../core/palette.dart';
import '../domain/sound.dart';
import 'sound_library.dart';
import 'storage.dart';

const _uuid = Uuid();

/// Why an imported file was turned away. Each one is a sentence the screen
/// can show as it is.
class ImportRejected implements Exception {
  const ImportRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The formats that can be brought in. WAV is read by the app itself; the
/// rest go through the engine's own decoder, which it already carries because
/// it can play them.
const List<String> kImportExtensions = ['wav', 'mp3', 'flac', 'ogg'];

/// Brings a sound in from the phone's storage.
///
/// It is decoded on the way in — that both proves it is really audio and
/// gives the duration — and written back out in the app's own format, so
/// everything in the library reads the same way afterwards.
///
/// Two decoders, and the order matters. A WAV at the app's own rate is read
/// here, exactly, with no engine involved. Anything else — a WAV at 48 kHz
/// included, which used to come in sounding slow and flat — is handed to
/// [decode], which reads it back at this app's rate whatever the file's was.
Future<Sound> importAudio({
  required SoundLibrary library,
  required Storage storage,
  required String sourcePath,
  required Future<Float32List?> Function(String path) decode,
}) async {
  final source = File(sourcePath);
  if (!await source.exists()) {
    throw const ImportRejected('El archivo ya no está donde estaba.');
  }

  Float32List? samples;
  var sampleRate = kSampleRate;

  if (sourcePath.toLowerCase().endsWith('.wav')) {
    try {
      final decoded = decodeWav(await source.readAsBytes());
      // A file already at our rate needs nobody: this is the exact path.
      if (decoded.sampleRate == kSampleRate) {
        samples = decoded.samples;
        sampleRate = decoded.sampleRate;
      }
    } on WavFormatException {
      // Not a WAV this app understands. The engine may still read it.
    }
  }

  samples ??= await decode(sourcePath);
  if (samples == null) {
    throw ImportRejected(
      'No se pudo leer el audio. Formatos que entran: '
      '${kImportExtensions.join(', ').toUpperCase()}.',
    );
  }

  final durationMs = (samples.length / sampleRate * 1000).round();
  if (durationMs > kMaxImportDuration.inMilliseconds) {
    throw ImportRejected(
      'Pasa de ${kMaxImportDuration.inSeconds} segundos: recórtalo antes.',
    );
  }
  if (samples.isEmpty) {
    throw const ImportRejected('El archivo no trae audio.');
  }

  final fileName = '${_uuid.v4()}.wav';
  final bytes = encodeWav(samples, sampleRate: sampleRate);
  await storage.soundFile(fileName).writeAsBytes(bytes);

  return library.add(Sound(
    id: _uuid.v4(),
    name: _nameFrom(sourcePath),
    family: SoundFamily.texture,
    fileName: fileName,
    origin: SoundOrigin.imported,
    durationMs: durationMs,
    sizeBytes: bytes.length,
  ));
}

/// The file name without its folders or extension, kept short enough to fit
/// on a pad label.
String _nameFrom(String path) {
  final base = path.split(Platform.pathSeparator).last;
  final withoutExtension =
      base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
  final clean = withoutExtension.trim();
  if (clean.isEmpty) return 'Importado';
  return clean.length <= 18 ? clean : clean.substring(0, 18);
}
