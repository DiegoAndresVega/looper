import '../audio/voices.dart';
import '../audio/wav_encoder.dart';
import '../core/constants.dart';
import '../core/palette.dart';
import '../domain/sound.dart';
import 'storage.dart';

/// Identifies the click everywhere: on the tempo clock and in the engine's
/// cache. It starts with an underscore so it can never collide with a uuid.
const String kMetronomeId = '_metronome';

/// The click, synthesised the first time it is switched on. It lives outside
/// the library on purpose: it is a tool, not a sound you can put on a pad.
Future<Sound> ensureMetronomeSound(Storage storage) async {
  const fileName = '$kMetronomeId.wav';
  final file = storage.soundFile(fileName);

  final samples = kVoices['metro']!(kSampleRate);
  if (!await file.exists()) {
    await file.writeAsBytes(encodeWav(samples, sampleRate: kSampleRate));
  }

  return Sound(
    id: kMetronomeId,
    name: 'Claqueta',
    family: SoundFamily.percussion,
    fileName: fileName,
    origin: SoundOrigin.factory_,
    durationMs: (samples.length / kSampleRate * 1000).round(),
    sizeBytes: await file.length(),
  );
}
