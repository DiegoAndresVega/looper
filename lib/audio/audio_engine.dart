import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/constants.dart';
import '../domain/sound.dart';
import 'family_fx.dart';
import 'fx_curves.dart';
import 'master_fx.dart';

/// Thin wrapper over SoLoud. Everything the instrument needs to make noise,
/// and nothing else. Sources are cached so a pad never reloads its file.
class AudioEngine {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};

  /// Master volume and performance effects. Their state outlives the engine,
  /// which is torn down whenever the sampler needs the audio session.
  final MasterFx fx = MasterFx();

  /// The four family buses and the reverb they share. Same deal: the knobs
  /// outlive the engine, the buses themselves do not.
  final FamilyFx buses = FamilyFx();

  /// The send twin fired alongside a voice, and the gain it went out at, so a
  /// pad that is stopped or muted stops feeding the reverb too. Only voices
  /// with their family's send up are in here.
  final Map<SoundHandle, ({SoundHandle handle, double gain})> _sends = {};

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await _soloud.init(
      sampleRate: kSampleRate,
      channels: Channels.stereo,
      bufferSize: 1024,
    );
    // SoLoud allows sixteen voices at once out of the box, and it drops the
    // quietest ones over that. Sixteen is nothing here: a handful of loops
    // retriggering, the sequencer and a roll go past it without trying, and
    // what a player hears is layers cutting out for no reason.
    _soloud.setMaxActiveVoiceCount(kMaxVoices);
    _ready = true;
    fx.apply();
    buses.attach();
  }

  /// Frees the engine so the recorder can own the audio session. iOS refuses
  /// to let both plugins hold it at once, which is why recording never runs
  /// while the session is playing.
  Future<void> release() async {
    if (!_ready) return;
    await stopAll();
    _sources.clear();
    // Before the deinit, never after: destroying a bus reaches into the
    // engine it belongs to.
    buses.detach();
    _soloud.deinit();
    _ready = false;
  }

  /// Loads a sound into memory, decoded and ready to fire with no latency.
  Future<void> preload(Sound sound, String path) async {
    if (!_ready || _sources.containsKey(sound.id)) return;
    try {
      _sources[sound.id] = await _soloud.loadFile(path, mode: LoadMode.memory);
    } on SoLoudException catch (e) {
      debugPrint('No se pudo cargar ${sound.name}: $e');
    }
  }

  bool isLoaded(String soundId) => _sources.containsKey(soundId);

  /// Decodes any file the engine can read into mono samples at the app's own
  /// rate, or null when it cannot be read.
  ///
  /// This is how MP3, FLAC and OGG get in: the app's own decoder only speaks
  /// WAV, and the engine already carries a decoder for everything it can
  /// play. It also fixes the WAV that arrives at 48 kHz — the read is asked
  /// for a number of samples spread over the file's *duration*, so what comes
  /// back is at this app's rate whatever the file's was.
  ///
  /// It runs off an isolate inside the plugin, so a sixty-second import does
  /// not freeze the grid.
  Future<Float32List?> decodeToSamples(String path) async {
    if (!_ready) return null;
    AudioSource? source;
    try {
      source = await _soloud.loadFile(path, mode: LoadMode.disk);
      final length = _soloud.getLength(source);
      if (length <= Duration.zero) return null;
      final wanted = (length.inMicroseconds / 1e6 * kSampleRate).round();
      if (wanted <= 0) return null;
      final samples = await _soloud.readSamplesFromFile(path, wanted);
      return samples.isEmpty ? null : samples;
    } on Object catch (e) {
      debugPrint('No se pudo decodificar $path: $e');
      return null;
    } finally {
      if (source != null) {
        await _soloud.disposeSource(source);
      }
    }
  }

  Future<void> unload(String soundId) async {
    final source = _sources.remove(soundId);
    if (source != null) {
      await _soloud.disposeSource(source);
    }
  }

  /// Fires a sound once. Returns null when the source never loaded.
  ///
  /// The voice travels on its family's bus, so the family's filter and grit
  /// colour it. Pass [dry] for the things that are not music — the click —
  /// which go straight to the master and answer to no family.
  ///
  /// When the family's send is up, a twin of the same voice is fired into the
  /// shared reverb at the send's gain. Only the dry handle comes back: the
  /// twin is the engine's business, and it is stopped, faded and panned with
  /// the voice it belongs to.
  SoundHandle? fire(
    Sound sound, {
    required double volume,
    required double rate,
    bool looping = false,
    double pan = 0,
    bool dry = false,
  }) {
    final source = _sources[sound.id];
    if (source == null || !_ready) return null;

    final handle = _start(
      source,
      sound,
      bus: dry ? null : buses.busFor(sound.family),
      volume: volume,
      rate: rate,
      looping: looping,
      pan: pan,
    );
    if (handle == null) return null;

    final reverb = buses.reverbBus;
    // The share of the voice that goes to the reverb, kept as the ratio and
    // not as the level: it is what the twin has to be re-scaled by whenever
    // the voice it shadows is faded.
    final share = dry ? 0.0 : buses.settingsFor(sound.family).sendVolume;
    if (reverb != null && volume * share > kFxEpsilon) {
      _pruneSends();
      final twin = _start(
        source,
        sound,
        bus: reverb,
        volume: volume * share,
        rate: rate,
        looping: looping,
        pan: pan,
      );
      if (twin != null) _sends[handle] = (handle: twin, gain: share);
    }
    return handle;
  }

  /// Starts one voice, on [bus] or straight on the engine when there is none.
  /// Both the dry voice and its send twin come through here, so they can never
  /// drift apart in trim, rate or pan.
  SoundHandle? _start(
    AudioSource source,
    Sound sound, {
    required Bus? bus,
    required double volume,
    required double rate,
    required bool looping,
    required double pan,
  }) {
    final start = Duration(milliseconds: sound.trimStartMs);
    final end = sound.trimEndMs == null
        ? null
        : Duration(milliseconds: sound.trimEndMs!);
    final level = volume.clamp(0.0, 1.0);

    final SoundHandle handle;
    try {
      handle = bus == null
          ? _soloud.play(
              source,
              volume: level,
              looping: looping,
              loopingStartAt: start,
              loopingEndAt: end,
            )
          : bus.play(
              source,
              volume: level,
              looping: looping,
              loopingStartAt: start,
              loopingEndAt: end,
            );
    } on SoLoudException catch (e) {
      debugPrint('No se pudo disparar ${sound.name}: $e');
      return null;
    }

    if (rate != 1.0) {
      _soloud.setRelativePlaySpeed(handle, rate);
    }
    if (pan != 0) {
      setHandlePan(handle, pan);
    }

    // Trimming is non-destructive: the file keeps its tail, playback just
    // skips in and bails out early. SoLoud only honours the loop points when
    // looping, so a one-shot needs the seek and the stop spelled out.
    if (sound.trimStartMs > 0) {
      _soloud.seek(handle, start);
    }
    if (!looping && sound.trimEndMs != null) {
      _soloud.scheduleStop(
        handle,
        Duration(milliseconds: (sound.trimmedDurationMs / rate).round()),
      );
    }
    return handle;
  }

  /// Whether a voice is still playing. A one-shot ends on its own and nobody
  /// is told, so anything holding a handle has to ask.
  bool isVoiceAlive(SoundHandle handle) =>
      _ready && _soloud.getIsValidVoiceHandle(handle);

  /// Drops the pairs whose dry voice has already finished. One-shots end on
  /// their own and nobody tells us, so the map is swept when it grows past
  /// what the engine can even play at once — never on every hit, which would
  /// put dozens of calls across the boundary in the middle of a roll.
  void _pruneSends() {
    if (_sends.length <= kMaxVoices) return;
    _sends.removeWhere((dry, _) => !_soloud.getIsValidVoiceHandle(dry));
  }

  /// The twin follows: a loop muted while it runs would otherwise keep
  /// feeding the reverb, and a muted pad you can still hear is not muted.
  void setHandleVolume(SoundHandle handle, double volume) {
    if (!_ready) return;
    _soloud.setVolume(handle, volume.clamp(0.0, 1.0));
    final send = _sends[handle];
    if (send != null) {
      _soloud.setVolume(send.handle, (volume * send.gain).clamp(0.0, 1.0));
    }
  }

  /// Where a voice sits in the stereo field, -1 hard left to 1 hard right.
  /// The engine has always run in stereo — only the files are mono — so this
  /// costs nothing but the call.
  void setHandlePan(SoundHandle handle, double pan) {
    if (!_ready) return;
    _soloud.setPan(handle, pan.clamp(-1.0, 1.0));
    final send = _sends[handle];
    if (send != null) {
      _soloud.setPan(send.handle, pan.clamp(-1.0, 1.0));
    }
  }

  /// Stopping a voice stops what it was sending. The reverb keeps ringing —
  /// it is a tail, and a tail that is cut is a fault, not a stop.
  Future<void> stopHandle(SoundHandle handle) async {
    if (!_ready) return;
    final send = _sends.remove(handle);
    await _soloud.stop(handle);
    if (send != null) {
      await _soloud.stop(send.handle);
    }
  }

  Future<void> stopAll() async {
    if (!_ready) return;
    await _soloud.disposeAllSources();
    _sources.clear();
    _sends.clear();
    // Every bus is a voice, and that call stops all of them. Without this the
    // grid goes quiet from here on: the sounds play into buses nobody hears.
    buses.rearm();
  }


  /// Captures the mixer output — this is how a take is recorded. It never
  /// touches the microphone, so it can run while the grid is being played.
  Stream<Uint8List> startMixdownCapture() {
    return _soloud.startMixerOutputStream(format: MixerOutputFormat.wav);
  }

  void stopMixdownCapture() => _soloud.stopMixerOutputStream();
}
