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

/// An imported file may be longer than a take, but not by much: the whole
/// thing is held decoded in memory so a pad fires without delay.
const Duration kMaxImportDuration = Duration(seconds: 60);

/// Tempo range and the tempo the app opens with.
const int kBpmMin = 40;
const int kBpmMax = 220;
const int kDefaultBpm = 92;

/// The step sequencer: one bar of 16th notes, and how many patterns a session
/// keeps. Sixteen steps on a sixteen pad grid means one pad is one step.
const int kPatternSteps = 16;
const int kPatternCount = 16;

/// Identifies the sequencer on the tempo clock. Underscored so it can never
/// collide with a pad key.
const String kSequencerKey = '_sequencer';

/// While recording steps by hand, notes played inside this window land on the
/// same step. It is what makes a chord a chord instead of four steps.
const Duration kChordWindow = Duration(milliseconds: 260);

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

/// The click sits under the music: loud enough to follow, never to lead.
const double kMetronomeVolume = 0.55;

/// Audio format used for every rendered and recorded sound.
const int kSampleRate = 44100;
const int kChannels = 1;

/// How many voices may sound at once. Sixty-four is a pad per voice with room
/// for their tails; the engine's own default of sixteen cuts layers short.
const int kMaxVoices = 64;

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

/// How long after the last edit the session is written to disk.
const Duration kSessionSaveDelay = Duration(milliseconds: 800);

/// Loop lengths offered in the pad sheet, in 16th notes: 1, 2, 4 and 8 beats.
const List<int> kLoopLengthChoices = [4, 8, 16, 32];

/// Buckets in the waveform drawn after a take. Enough to read the shape of a
/// hit without turning into a comb.
const int kWaveformBuckets = 96;
