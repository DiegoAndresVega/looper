import 'package:flutter/foundation.dart';
import 'package:flutter_recorder/flutter_recorder.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../data/storage.dart';
import 'wav_decoder.dart';

/// Why the microphone could not be opened. The screen turns each of these
/// into a sentence the player can act on.
enum MicFailure {
  permissionDenied,
  permissionPermanentlyDenied,
  deviceUnavailable,
  nothingCaptured,
}

/// What comes back from a sample: mono samples plus the rate the device
/// actually gave, which is not always the one that was asked for.
class CapturedSample {
  const CapturedSample({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;

  int get durationMs => (samples.length / sampleRate * 1000).round();
}

class MicException implements Exception {
  const MicException(this.failure, this.message);

  final MicFailure failure;
  final String message;

  @override
  String toString() => 'MicException(${failure.name}): $message';
}

/// The microphone, from permission to samples on disk.
///
/// It owns the capture device for exactly as long as a sample lasts. The
/// playback engine must be released before [open] and re-initialised after
/// [close]: the two never hold the system audio session at the same time.
class MicRecorder {
  MicRecorder(this._storage);

  final Storage _storage;
  final Recorder _recorder = Recorder.instance;

  bool _open = false;
  bool _capturing = false;
  DateTime? _startedAt;

  bool get isOpen => _open;
  bool get isCapturing => _capturing;

  /// How long the current sample has been running. Zero when nothing is being
  /// captured, so the screen can show a resting timer.
  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  /// Asks for the microphone, returning only when the answer is known.
  /// Throws [MicException] when the answer is no, telling the two kinds of
  /// no apart so the screen can offer the settings shortcut.
  Future<void> ensurePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted || status.isLimited) return;
    if (status.isPermanentlyDenied) {
      throw const MicException(
        MicFailure.permissionPermanentlyDenied,
        'El micrófono está bloqueado en los ajustes del sistema.',
      );
    }
    throw const MicException(
      MicFailure.permissionDenied,
      'Sin micrófono no se puede grabar.',
    );
  }

  /// Opens the capture device. Float samples are used because that is the
  /// only format the level meter can read.
  Future<void> open() async {
    if (_open) return;
    await ensurePermission();
    try {
      await _recorder.init(
        format: PCMFormat.f32le,
        sampleRate: kSampleRate,
        channels: RecorderChannels.mono,
      );
      _recorder.start();
      _open = true;
    } on Exception catch (e) {
      throw MicException(
        MicFailure.deviceUnavailable,
        'No se pudo abrir el micrófono: $e',
      );
    }
  }

  /// Releases the device so the playback engine can have the audio session
  /// back. Safe to call twice.
  Future<void> close() async {
    if (!_open) return;
    if (_capturing) {
      _recorder.stopRecording();
      _capturing = false;
    }
    _startedAt = null;
    _recorder.deinit();
    _open = false;
  }

  /// Current input level as 0..1, ready to paint. Silence sits at zero
  /// instead of at the -60 dB floor.
  double get level {
    if (!_open) return 0;
    try {
      final db = _recorder.getVolumeDb();
      if (!db.isFinite) return 0;
      return ((db - kMicFloorDb) / -kMicFloorDb).clamp(0.0, 1.0);
    } on Exception {
      return 0;
    }
  }

  Future<void> startCapture() async {
    if (!_open || _capturing) return;
    final scratch = _storage.captureScratch;
    if (await scratch.exists()) {
      await scratch.delete();
    }
    _recorder.startRecording(
      completeFilePath: scratch.path,
      format: RecordingFormat.wav,
    );
    _capturing = true;
    _startedAt = DateTime.now();
  }

  /// Stops the sample and hands back the samples: mono, capped at ten seconds
  /// and lifted to a usable level. Throws [MicException] when nothing landed.
  Future<CapturedSample> stopCapture() async {
    if (!_capturing) {
      throw const MicException(MicFailure.nothingCaptured, 'No había toma.');
    }
    _recorder.stopRecording();
    _capturing = false;
    _startedAt = null;

    final scratch = _storage.captureScratch;
    if (!await scratch.exists()) {
      throw const MicException(
        MicFailure.nothingCaptured,
        'La grabación no llegó a escribirse.',
      );
    }

    try {
      final decoded = decodeWav(await scratch.readAsBytes());
      final capped =
          capToMaxDuration(decoded.samples, sampleRate: decoded.sampleRate);
      if (capped.length < kMinRecordSamples) {
        throw const MicException(
          MicFailure.nothingCaptured,
          'La toma es demasiado corta.',
        );
      }
      return CapturedSample(
        samples: normalized(capped, peak: kRecordNormalisePeak),
        sampleRate: decoded.sampleRate,
      );
    } on WavFormatException catch (e) {
      debugPrint('Toma ilegible: $e');
      throw const MicException(
        MicFailure.nothingCaptured,
        'La grabación salió ilegible.',
      );
    }
  }

  /// Throws away the scratch file after a sample is discarded or saved.
  Future<void> clearScratch() async {
    final scratch = _storage.captureScratch;
    if (await scratch.exists()) {
      await scratch.delete();
    }
  }
}
