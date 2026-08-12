/// Fixed limits of the instrument. Nothing here is user-configurable.
library;

/// Pads per bank: a 4x4 grid.
const int kPadsPerBank = 16;
const int kGridColumns = 4;

/// Banks A, B, C, D — 64 pads in total.
const int kBankCount = 4;
const List<String> kBankIds = ['A', 'B', 'C', 'D'];

/// A recorded sound never exceeds ten seconds.
const Duration kMaxRecordDuration = Duration(seconds: 10);

/// Tempo range and the tempo the app opens with.
const int kBpmMin = 40;
const int kBpmMax = 220;
const int kDefaultBpm = 92;

/// The scheduler resolution: every loop length is a multiple of a 16th note.
const int kStepsPerBeat = 4;
const int kStepsPerBar = 16;

/// How often the tempo clock wakes up. Short enough that step jitter stays
/// under ~8 ms, which a player does not hear as sloppy.
const Duration kSchedulerTick = Duration(milliseconds: 8);

/// Tempo stepper acceleration: a tap moves one unit, holding speeds up twice.
const Duration kStepperHoldDelay = Duration(milliseconds: 500);
const Duration kStepperRepeatInterval = Duration(milliseconds: 250);
const Duration kStepperFastThreshold = Duration(milliseconds: 1500);
const int kStepperFastAmount = 3;

/// A long press on a pad opens its sheet.
const Duration kPadLongPress = Duration(milliseconds: 320);

/// Roll (retrigger) divisions offered while the ROLL button is held, in steps.
const List<int> kRollDivisions = [2, 1]; // 1/8 and 1/16 of a bar

/// Audio format used for every rendered and recorded sound.
const int kSampleRate = 44100;
const int kChannels = 1;

/// Warn when the device drops below this much free space.
const int kLowSpaceBytes = 200 * 1024 * 1024;

/// Bottom of the input level meter. Below this a take reads as silence.
const double kMicFloorDb = -60;

/// A take shorter than this is a slip of the finger, not a sound.
const int kMinRecordSamples = kSampleRate ~/ 20; // 50 ms

/// Recordings are lifted to this peak so they sit level with the factory kit.
const double kRecordNormalisePeak = 0.9;

/// How often the recording screen redraws the meter and the timer.
const Duration kMeterTick = Duration(milliseconds: 60);

/// Buckets in the waveform drawn after a take. Enough to read the shape of a
/// hit without turning into a comb.
const int kWaveformBuckets = 96;
