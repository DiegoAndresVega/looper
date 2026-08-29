import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';
import '../../data/sound_import.dart';
import '../../data/sound_library.dart';
import '../../data/storage.dart';
import '../../domain/sound.dart';
import '../../domain/synth_patch.dart';
import '../../audio/chopper.dart';
import 'chop_sheet.dart';
import 'sound_list.dart';
import 'sound_sheet.dart';
import 'synth_sheet.dart';

/// Everything the instrument can play: the factory kit, your takes and what
/// you brought in. Tapping a sound opens its editor; the list itself is the
/// same one the pad sheet uses.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.library,
    required this.storage,
    required this.onPreview,
    required this.onDelete,
    required this.slicesFor,
    required this.onReverse,
    required this.onPitch,
    required this.onStretch,
    required this.sessionBpm,
    required this.onDecodeAudio,
    this.lowSpaceLabel,
    required this.onAuditionPatch,
    required this.onCreatePatch,
    required this.onChop,
  });

  final SoundLibrary library;
  final Storage storage;

  /// Plays a sound with its current edits applied.
  final Future<void> Function(Sound sound) onPreview;

  /// Removes the sound and empties any pad that was holding it.
  final Future<void> Function(Sound sound) onDelete;

  /// Where the cuts would fall, for the sheet to draw before committing.
  final Future<List<Slice>> Function(Sound sound, ChopMode mode) slicesFor;

  /// Writes the sound backwards into a file of its own, and hands back what
  /// it became. Null when the audio could not be read.
  final Future<Sound?> Function(Sound sound) onReverse;

  /// Transposes for real and stretches to the session's tempo. Both rewrite
  /// the sound's file, so both go through the instrument like the reverse.
  final Future<Sound?> Function(Sound sound, int semitones) onPitch;
  final Future<Sound?> Function(Sound sound, double fromBpm) onStretch;

  /// The tempo of the open session, which is what stretching aims at.
  final int sessionBpm;

  /// Decodes anything the engine can read into samples at the app's own rate.
  /// It is how MP3, FLAC and OGG get in — and how a WAV at 48 kHz stops
  /// coming in slow and flat.
  final Future<Float32List?> Function(String path) onDecodeAudio;

  /// Plays a patch without keeping it, and keeps one. The synthesiser lives
  /// in the engine, so both go through the instrument.
  /// What is left on the device, but only when it is little enough to say.
  /// Null the rest of the time, which is nearly always.
  final String? lowSpaceLabel;

  final Future<void> Function(SynthPatch patch) onAuditionPatch;
  final Future<void> Function(SynthPatch patch, String name) onCreatePatch;

  /// Cuts the sound across the grid. Null when no bank has room.
  final Future<({int bank, int slot, int count})?> Function(
    Sound sound,
    List<Slice> slices,
  ) onChop;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String? _message;
  bool _importing = false;

  SoundLibrary get _library => widget.library;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              if (_message != null) ...[
                const SizedBox(height: 12),
                _messagePanel(_message!),
              ],
              Expanded(
                child: SoundList(
                  sounds: _library.sounds,
                  selectedId: null,
                  onPick: _openSound,
                  trailing: _playButton,
                  padding: const EdgeInsets.only(bottom: 12),
                ),
              ),
              Row(
                children: [
                  Expanded(child: _synthButton()),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: _importButton()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
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
        Expanded(
          child: Text('Biblioteca', style: Brand.title(17)),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_library.count} · ${_formatSize(_library.sizeBytes)}',
              style: Brand.readout(10, color: Palette.inkFaint),
            ),
            // Only when it matters. A running total of free space is noise;
            // a warning that appears the day it is true is information.
            if (widget.lowSpaceLabel != null) ...[
              const SizedBox(height: 3),
              Text(
                'Quedan ${widget.lowSpaceLabel}',
                style: Brand.readout(9, color: Palette.rec),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _playButton(Sound sound) {
    return GestureDetector(
      onTap: () => widget.onPreview(sound),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Palette.line),
        ),
        child: Icon(Icons.play_arrow, size: 16, color: sound.family.color),
      ),
    );
  }

  /// The synthesiser that was always in the binary, now with a door.
  Widget _synthButton() {
    return GestureDetector(
      onTap: _openSynth,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.accent),
        ),
        child: Text(
          'SINTETIZAR',
          style: Brand.label(9, weight: 700, color: Palette.accent),
        ),
      ),
    );
  }

  Future<void> _openSynth() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SynthSheet(
        onAudition: widget.onAuditionPatch,
        onCreate: (patch, name) async {
          await widget.onCreatePatch(patch, name);
          if (mounted) setState(() => _message = '$name está en la biblioteca.');
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _importButton() {
    return GestureDetector(
      onTap: _importing ? null : _import,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          _importing ? 'IMPORTANDO…' : 'IMPORTAR UN SONIDO',
          style: Brand.label(9, weight: 700, color: Palette.inkDim),
        ),
      ),
    );
  }

  Widget _messagePanel(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Palette.line),
      ),
      child: Text(message, style: Brand.body(11.5)),
    );
  }

  Future<void> _openSound(Sound sound) async {
    final peaks = await _library.peaksFor(sound);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SoundSheet(
        sound: sound,
        peaks: peaks,
        onChanged: _library.update,
        onReverse: widget.onReverse,
        onPitch: widget.onPitch,
        onStretch: widget.onStretch,
        onDetectTempo: _library.tempoOf,
        onPeaks: _library.peaksFor,
        sessionBpm: widget.sessionBpm,
        onPreview: widget.onPreview,
        onDelete: () => _delete(sound),
        onChop: () {
          Navigator.of(context).pop();
          _openChop(sound);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// Cutting is a preview until it is confirmed: the sheet hands back the
  /// slices it drew and only then is anything created.
  Future<void> _openChop(Sound sound) async {
    final peaks = await _library.peaksFor(sound);
    if (!mounted) return;

    final slices = await showModalBottomSheet<List<Slice>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChopSheet(
        sound: sound,
        peaks: peaks,
        slicesFor: (mode) => widget.slicesFor(sound, mode),
      ),
    );
    if (slices == null || !mounted) return;

    final landed = await widget.onChop(sound, slices);
    if (!mounted) return;
    setState(() {
      _message = landed == null
          ? 'No hay ${slices.length} pads libres seguidos en ningún banco.'
          : '${sound.name} en ${landed.count} pads del banco '
              '${kBankIds[landed.bank]}.';
    });
  }

  Future<void> _delete(Sound sound) async {
    await widget.onDelete(sound);
    if (!mounted) return;
    setState(() => _message = '${sound.name} borrado.');
  }

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _message = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Elige un sonido',
        type: FileType.custom,
        allowedExtensions: kImportExtensions,
      );
      final files = picked?.files ?? const [];
      final path = files.isEmpty ? null : files.first.path;
      if (path == null) return;

      final sound = await importAudio(
        library: _library,
        storage: widget.storage,
        sourcePath: path,
        decode: widget.onDecodeAudio,
      );
      if (!mounted) return;
      setState(() => _message = '${sound.name} está en la biblioteca.');
    } on ImportRejected catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
