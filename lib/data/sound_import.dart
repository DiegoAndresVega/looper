import 'dart:io';

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

/// Brings a WAV in from the phone's storage.
///
/// The file is decoded on the way in — that both proves it is really a WAV and
/// gives the duration — and written back out in the app's own format, so
/// everything in the library reads the same way.
Future<Sound> importWav({
  required SoundLibrary library,
  required Storage storage,
  required String sourcePath,
}) async {
  final source = File(sourcePath);
  if (!await source.exists()) {
    throw const ImportRejected('El archivo ya no está donde estaba.');
  }

  final DecodedWav decoded;
  try {
    decoded = decodeWav(await source.readAsBytes());
  } on WavFormatException catch (e) {
    throw ImportRejected('No es un WAV que se pueda leer: ${e.message}');
  }

  if (decoded.durationMs > kMaxImportDuration.inMilliseconds) {
    throw ImportRejected(
      'Pasa de ${kMaxImportDuration.inSeconds} segundos: recórtalo antes.',
    );
  }
  if (decoded.samples.isEmpty) {
    throw const ImportRejected('El archivo no trae audio.');
  }

  final fileName = '${_uuid.v4()}.wav';
  final bytes = encodeWav(decoded.samples, sampleRate: decoded.sampleRate);
  await storage.soundFile(fileName).writeAsBytes(bytes);

  return library.add(Sound(
    id: _uuid.v4(),
    name: _nameFrom(sourcePath),
    family: SoundFamily.texture,
    fileName: fileName,
    origin: SoundOrigin.imported,
    durationMs: decoded.durationMs,
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
