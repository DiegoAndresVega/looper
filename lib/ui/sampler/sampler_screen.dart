import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../../audio/audio_engine.dart';
import '../../audio/mic_recorder.dart';
import '../../audio/wav_decoder.dart';
import '../../audio/wav_encoder.dart';
import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../data/session_store.dart';
import '../../data/sound_library.dart';
import '../../data/storage.dart';
import '../../domain/sound.dart';
import 'sample_button.dart';
import 'sample_review.dart';

const _uuid = Uuid();

enum _Phase { idle, recording, review }

/// Capture a sound of up to ten seconds and keep it in the library.
///
/// The screen is silent on purpose: the caller stops the session and releases
/// the playback engine before pushing it, so the microphone never hears the
/// speaker. The engine only comes back up to preview the sample.
class SamplerScreen extends StatefulWidget {
  const SamplerScreen({
    super.key,
    required this.engine,
    required this.library,
    required this.storage,
  });

  final AudioEngine engine;
  final SoundLibrary library;
  final Storage storage;

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final MicRecorder _mic = MicRecorder(widget.storage);
  final TextEditingController _name = TextEditingController();

  _Phase _phase = _Phase.idle;
  Timer? _meterTicker;
  Timer? _previewTimer;
  double _level = 0;
  Duration _elapsed = Duration.zero;

  Float32List _peaks = Float32List(0);
  Sound? _sample;
  SoundFamily _family = SoundFamily.voice;
  SoundHandle? _previewHandle;

  String? _error;
  bool _blockedInSettings = false;
  bool _busy = false;

  @override
  void dispose() {
    _meterTicker?.cancel();
    _previewTimer?.cancel();
    _name.dispose();
    _mic.close();
    super.dispose();
  }

  // --------------------------------------------------------------- recording

  Future<void> _startRecording() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _blockedInSettings = false;
    });

    try {
      // The two engines never hold the audio session at once.
      await widget.engine.release();
      await _mic.open();
      await _mic.startCapture();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.recording;
        _elapsed = Duration.zero;
        _level = 0;
      });
      _meterTicker = Timer.periodic(kMeterTick, (_) => _onMeterTick());
    } on MicException catch (e) {
      await _mic.close();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _blockedInSettings =
            e.failure == MicFailure.permissionPermanentlyDenied;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onMeterTick() {
    if (!mounted) return;
    final elapsed = _mic.elapsed;
    setState(() {
      _level = _mic.level;
      _elapsed = elapsed;
    });
    if (elapsed >= kMaxRecordDuration) {
      _stopRecording();
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || _phase != _Phase.recording) return;
    _meterTicker?.cancel();
    setState(() => _busy = true);

    try {
      final sample = await _mic.stopCapture();
      await _mic.close();

      final fileName = '${_uuid.v4()}.wav';
      final bytes = encodeWav(sample.samples, sampleRate: sample.sampleRate);
      await widget.storage.soundFile(fileName).writeAsBytes(bytes);
      await _mic.clearScratch();

      final sound = Sound(
        id: 'preview_$fileName',
        name: _defaultName(),
        family: _family,
        fileName: fileName,
        origin: SoundOrigin.recorded,
        durationMs: sample.durationMs,
        sizeBytes: bytes.length,
      );

      // Back to the playback engine, now that the microphone is closed.
      await widget.engine.init();
      await widget.engine.preload(sound, widget.storage.soundFile(fileName).path);

      if (!mounted) return;
      setState(() {
        _sample = sound;
        _peaks = peakEnvelope(sample.samples, kWaveformBuckets);
        _name.text = sound.name;
        _phase = _Phase.review;
      });
    } on MicException catch (e) {
      await _mic.close();
      await widget.engine.init();
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _phase = _Phase.idle;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _defaultName() {
    final mine = widget.library.byOrigin(SoundOrigin.recorded).length + 1;
    return 'Mío $mine';
  }

  // ----------------------------------------------------------------- preview

  void _togglePreview() {
    final sample = _sample;
    if (sample == null) return;

    if (_previewHandle != null) {
      _stopPreview();
      return;
    }
    final handle = widget.engine.fire(sample, volume: 1.0, rate: 1.0);
    if (handle == null) {
      setState(() => _error = 'El sample no se pudo reproducir.');
      return;
    }
    setState(() => _previewHandle = handle);
    _previewTimer = Timer(
      Duration(milliseconds: sample.durationMs + 60),
      () => mounted ? _stopPreview() : null,
    );
  }

  void _stopPreview() {
    final handle = _previewHandle;
    _previewTimer?.cancel();
    if (handle != null) {
      widget.engine.stopHandle(handle);
    }
    if (mounted) setState(() => _previewHandle = null);
  }

  // -------------------------------------------------------------- keep or go

  Future<void> _discardSample() async {
    final sample = _sample;
    _stopPreview();
    if (sample != null) {
      await widget.engine.unload(sample.id);
      final file = widget.storage.soundFile(sample.fileName);
      if (await file.exists()) await file.delete();
    }
    if (!mounted) return;
    setState(() {
      _sample = null;
      _peaks = Float32List(0);
      _phase = _Phase.idle;
    });
  }

  Future<void> _save() async {
    final sample = _sample;
    if (sample == null || _busy) return;
    _stopPreview();
    setState(() => _busy = true);

    // The preview source is cached under a throwaway id; the saved sound gets
    // its own and is loaded again when it lands on a pad.
    await widget.engine.unload(sample.id);

    final name = _name.text.trim();
    final sound = await registerRecording(
      library: widget.library,
      fileName: sample.fileName,
      name: name.isEmpty ? _defaultName() : name,
      family: _family,
      durationMs: sample.durationMs,
      sizeBytes: sample.sizeBytes,
    );

    if (!mounted) return;
    Navigator.of(context).pop(sound);
  }

  Future<void> _exit() async {
    _meterTicker?.cancel();
    _stopPreview();
    if (_phase == _Phase.recording) {
      await _mic.close();
      await _mic.clearScratch();
    }
    if (_phase == _Phase.review) {
      await _discardSample();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Palette.ground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _errorPanel(_error!),
                ],
                Expanded(
                  child: _phase == _Phase.review ? _reviewBody() : _captureBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: _exit,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Palette.line),
            ),
            child: const Icon(Icons.arrow_back, size: 16, color: Palette.inkDim),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'Samplear',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
        ),
      ],
    );
  }

  Widget _captureBody() {
    final recording = _phase == _Phase.recording;
    final progress =
        _elapsed.inMilliseconds / kMaxRecordDuration.inMilliseconds;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          recording
              ? _formatElapsed(_elapsed)
              : 'Hasta ${kMaxRecordDuration.inSeconds} segundos',
          style: TextStyle(
            fontSize: recording ? 34 : 13,
            fontWeight: recording ? FontWeight.w300 : FontWeight.w500,
            letterSpacing: recording ? -1 : 0.3,
            color: recording ? Palette.ink : Palette.inkDim,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 28),
        SampleButton(
          isRecording: recording,
          level: _level,
          progress: progress,
          onTap: recording ? _stopRecording : _startRecording,
        ),
        const SizedBox(height: 28),
        Text(
          recording ? 'Toca para parar' : 'Toca para samplear',
          style: const TextStyle(
            fontSize: 12,
            letterSpacing: 0.4,
            color: Palette.inkFaint,
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'La sesión se para mientras sampleas: el micrófono nunca oye lo que suena.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.5, color: Palette.inkFaint),
          ),
        ),
      ],
    );
  }

  Widget _reviewBody() {
    final sample = _sample!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 20),
      child: SampleReview(
        peaks: _peaks,
        durationMs: sample.durationMs,
        name: _name,
        family: _family,
        isPlaying: _previewHandle != null,
        onFamilyChanged: (f) => setState(() => _family = f),
        onTogglePlay: _togglePreview,
        onDiscard: _discardSample,
        onSave: _save,
      ),
    );
  }

  Widget _errorPanel(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.rec),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_off, size: 16, color: Palette.rec),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: Palette.ink,
              ),
            ),
          ),
          if (_blockedInSettings)
            GestureDetector(
              onTap: openAppSettings,
              child: const Text(
                'AJUSTES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: Palette.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatElapsed(Duration elapsed) {
    final seconds = elapsed.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)} s';
  }
}
