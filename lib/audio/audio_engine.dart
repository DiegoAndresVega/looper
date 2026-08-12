import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/constants.dart';
import '../domain/sound.dart';
import 'master_fx.dart';

/// Thin wrapper over SoLoud. Everything the instrument needs to make noise,
/// and nothing else. Sources are cached so a pad never reloads its file.
class AudioEngine {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, AudioSource> _sources = {};

  /// Master volume and performance effects. Their state outlives the engine,
  /// which is torn down whenever the sampler needs the audio session.
  final MasterFx fx = MasterFx();

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await _soloud.init(
      sampleRate: kSampleRate,
      channels: Channels.stereo,
      bufferSize: 1024,
    );
    _ready = true;
    fx.apply();
  }

  /// Frees the engine so the recorder can own the audio session. iOS refuses
  /// to let both plugins hold it at once, which is why recording never runs
  /// while the session is playing.
  Future<void> release() async {
    if (!_ready) return;
    await stopAll();
    _sources.clear();
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

  Future<void> unload(String soundId) async {
    final source = _sources.remove(soundId);
    if (source != null) {
      await _soloud.disposeSource(source);
    }
  }

  /// Fires a sound once. Returns null when the source never loaded.
  SoundHandle? fire(
    Sound sound, {
    required double volume,
    required double rate,
    bool looping = false,
  }) {
    final source = _sources[sound.id];
    if (source == null || !_ready) return null;

    final start = Duration(milliseconds: sound.trimStartMs);
    final end = sound.trimEndMs == null
        ? null
        : Duration(milliseconds: sound.trimEndMs!);

    final handle = _soloud.play(
      source,
      volume: volume.clamp(0.0, 1.0),
      looping: looping,
      loopingStartAt: start,
      loopingEndAt: end,
    );
    if (rate != 1.0) {
      _soloud.setRelativePlaySpeed(handle, rate);
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

  void setHandleVolume(SoundHandle handle, double volume) {
    if (!_ready) return;
    _soloud.setVolume(handle, volume.clamp(0.0, 1.0));
  }

  Future<void> stopHandle(SoundHandle handle) async {
    if (!_ready) return;
    await _soloud.stop(handle);
  }

  Future<void> stopAll() async {
    if (!_ready) return;
    await _soloud.disposeAllSources();
    _sources.clear();
  }


  /// Captures the mixer output — this is how a take is recorded. It never
  /// touches the microphone, so it can run while the grid is being played.
  Stream<Uint8List> startMixdownCapture() {
    return _soloud.startMixerOutputStream(format: MixerOutputFormat.wav);
  }

  void stopMixdownCapture() => _soloud.stopMixerOutputStream();

  /// The real WAV header, only known once the capture has stopped: the one
  /// that opened the stream carries placeholder sizes.
  Uint8List mixdownWavHeader() => _soloud.getMixerOutputWavHeader();
}
