import '../core/constants.dart';
import '../core/palette.dart';

/// One slot of a factory bank: the sound to render and how it behaves by
/// default when the pad is switched to loop.
class FactoryPad {
  const FactoryPad(this.name, this.family, this.voiceId, this.loopSteps);

  final String name;
  final SoundFamily family;
  final String voiceId;
  final int loopSteps;

  /// Stable id so a re-render never duplicates the sound.
  String get soundId => 'factory_$voiceId';
}

/// Bank A — what the app plays the very first time it opens.
const List<FactoryPad> kBankA = [
  FactoryPad('Bombo', SoundFamily.percussion, 'kick', 4),
  FactoryPad('Caja', SoundFamily.percussion, 'snare', 8),
  FactoryPad('Hat', SoundFamily.percussion, 'hat', 2),
  FactoryPad('Palma', SoundFamily.percussion, 'clap', 8),
  FactoryPad('Snap', SoundFamily.percussion, 'snap', 4),
  FactoryPad('Tom', SoundFamily.percussion, 'tom', 8),
  FactoryPad('Rim', SoundFamily.percussion, 'rim', 4),
  FactoryPad('Shaker', SoundFamily.percussion, 'shaker', 2),
  FactoryPad('Bajo', SoundFamily.tone, 'bass', 8),
  FactoryPad('Acorde', SoundFamily.tone, 'chord', 16),
  FactoryPad('Campana', SoundFamily.tone, 'bell', 16),
  FactoryPad('Pad', SoundFamily.texture, 'pad', 16),
  FactoryPad('Voz 1', SoundFamily.voice, 'voxA', 8),
  FactoryPad('Voz 2', SoundFamily.voice, 'voxB', 16),
  FactoryPad('Botella', SoundFamily.texture, 'bottle', 8),
  FactoryPad('Vinilo', SoundFamily.texture, 'vinyl', 16),
];

/// Bank B — four hard kicks up top, a full row of acid at the bottom.
const List<FactoryPad> kBankB = [
  FactoryPad('Bombo HT', SoundFamily.percussion, 'kickHT', 4),
  FactoryPad('Bombo DST', SoundFamily.percussion, 'kickDst', 4),
  FactoryPad('Rumble', SoundFamily.percussion, 'rumble', 8),
  FactoryPad('Kick Seco', SoundFamily.percussion, 'kickPnch', 4),
  FactoryPad('Clap IND', SoundFamily.percussion, 'clapInd', 8),
  FactoryPad('Hat Off', SoundFamily.percussion, 'hatOff', 2),
  FactoryPad('Hat Abt', SoundFamily.percussion, 'hatOpen', 4),
  FactoryPad('Zap', SoundFamily.percussion, 'zap', 4),
  FactoryPad('Acid 1', SoundFamily.tone, 'acid1', 8),
  FactoryPad('Acid 2', SoundFamily.tone, 'acid2', 8),
  FactoryPad('Acid Slide', SoundFamily.tone, 'acid3', 16),
  FactoryPad('Squelch', SoundFamily.tone, 'squelch', 16),
  FactoryPad('Sirena', SoundFamily.texture, 'siren', 16),
  FactoryPad('Riser', SoundFamily.texture, 'riser', 16),
  FactoryPad('Impacto', SoundFamily.texture, 'impact', 16),
  FactoryPad('Ruido', SoundFamily.texture, 'noiseWash', 16),
];

/// Banks C and D start empty on purpose: C fills up with your own recordings,
/// D is yours to arrange.
const Map<int, List<FactoryPad>> kFactoryBanks = {0: kBankA, 1: kBankB};

/// Every factory sound, in render order.
List<FactoryPad> get kAllFactoryPads => [...kBankA, ...kBankB];

const List<String> kBankLabels = ['Kit', 'Techno', 'Mías', 'Libre'];

/// Sanity check used by the tests: the grid is 4x4 and the labels line up.
bool get isFactoryKitWellFormed =>
    kBankA.length == kPadsPerBank &&
    kBankB.length == kPadsPerBank &&
    kBankLabels.length == kBankCount;
