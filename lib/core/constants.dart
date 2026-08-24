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

/// How far the pitch knob reaches, in semitones either way. An octave up and
/// an octave down is as far as a sample survives being stretched like tape.
const int kPadPitchRange = 12;

/// Roll (retrigger) divisions offered while the ROLL button is held, in steps.
const List<int> kRollDivisions = [2, 1]; // 1/8 and 1/16 of a bar

/// Swing: the share of each eighth note the first of its two sixteenths takes.
/// A half is dead straight; two thirds is a triplet. Past three quarters the
/// second note is so late it stops reading as a subdivision at all.
const double kSwingMin = 0.5;
const double kSwingMax = 0.75;
const double kSwingDefault = kSwingMin;

/// The swing settings worth naming on the way up: straight, the MPC's own
/// hip-hop feel, and the triplet.
const List<double> kSwingMarks = [0.5, 0.58, 2 / 3];

/// How hard a step hits. Full is the default — accents are made by holding
/// steps back, never by pushing one past the rest. The floor is not zero: a
/// step that makes no sound is a step you meant to erase.
const double kVelocityMin = 0.1;
const double kVelocityMax = 1.0;

/// The floor of a step's chance of sounding. Zero would mean «nunca», and a
/// step that never sounds is a step you meant to erase.
const double kProbabilityMin = 0.1;

/// How far a step can be pushed off the grid, in fractions of a step. Half a
/// step in either direction: past that it stops being feel and becomes the
/// neighbouring sixteenth.
const double kNudgeMax = 0.5;

/// The most hits a ratchet packs into one step. Four thirty-seconds in a
/// sixteenth is already a buzz; more is a tone.
const int kRatchetMax = 4;

/// How many step lights fit in a pad's corner before they reach the family
/// dot on the other side. A step with more voices than this still reads as
/// «a lot», which is all the number is for at that point.
const int kMaxStepDots = 4;

/// How many named snapshots a session keeps. Eight covers an afternoon, and
/// the cap is per session so filling one never eats another's.
const int kSavePointsPerSession = 8;

/// How many steps back the instrument remembers. Every entry is a snapshot of
/// an immutable session, so the cost is references rather than data; the cap
/// is there to bound it at all, not because twenty is expensive.
const int kUndoLimit = 20;

/// How much of the master is always kept in reach. Thirty seconds of stereo
/// at 44.1 kHz is about five megabytes — cheap enough to hold forever, long
/// enough to cover the loop you just played and liked.
const int kSkipBackSeconds = 30;

/// The note the first pad answers to. 36 is C1 in the convention Akai,
/// Novation and the M-Vave all share, so a pad controller works the moment it
/// is plugged in without anyone opening a settings screen.
const int kMidiPadBaseNote = 36;

/// The click sits under the music: loud enough to follow, never to lead.
const double kMetronomeVolume = 0.55;

/// The one of the bar, a fifth up and a touch louder. Same 50 ms sine played
/// faster — how drum machines have made this accent since they had one sound
/// to spare.
const double kMetronomeAccentRate = 1.5;
const double kMetronomeAccentVolume = 0.7;

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
