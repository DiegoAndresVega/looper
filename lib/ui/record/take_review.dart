import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/palette.dart';
import 'waveform_view.dart';

/// What is offered once a take exists: hear it, name it, say what kind of
/// sound it is, and either keep it or throw it away and go again.
class TakeReview extends StatelessWidget {
  const TakeReview({
    super.key,
    required this.peaks,
    required this.durationMs,
    required this.name,
    required this.family,
    required this.isPlaying,
    required this.onFamilyChanged,
    required this.onTogglePlay,
    required this.onDiscard,
    required this.onSave,
  });

  final Float32List peaks;
  final int durationMs;
  final TextEditingController name;
  final SoundFamily family;
  final bool isPlaying;
  final ValueChanged<SoundFamily> onFamilyChanged;
  final VoidCallback onTogglePlay;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(
            color: Palette.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WaveformView(peaks: peaks, color: family.color),
              const SizedBox(height: 12),
              Row(
                children: [
                  _playButton(),
                  const SizedBox(width: 12),
                  Text(
                    '${(durationMs / 1000).toStringAsFixed(1)} s',
                    style: const TextStyle(
                      color: Palette.inkDim,
                      fontSize: 12,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _nameField(),
        const SizedBox(height: 16),
        _familyRow(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _button(
                label: 'Repetir',
                onTap: onDiscard,
                background: Colors.transparent,
                foreground: Palette.inkDim,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _button(
                label: 'Guardar en el banco C',
                onTap: onSave,
                background: Palette.accent,
                foreground: Palette.ground,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playButton() {
    return GestureDetector(
      onTap: onTogglePlay,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isPlaying ? family.color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: family.color),
        ),
        child: Icon(
          isPlaying ? Icons.stop : Icons.play_arrow,
          size: 20,
          color: isPlaying ? Palette.ground : family.color,
        ),
      ),
    );
  }

  Widget _nameField() {
    return TextField(
      controller: name,
      maxLength: 18,
      style: const TextStyle(color: Palette.ink, fontSize: 15),
      cursorColor: Palette.accent,
      decoration: InputDecoration(
        counterText: '',
        labelText: 'Nombre',
        labelStyle: const TextStyle(color: Palette.inkFaint, fontSize: 12),
        filled: true,
        fillColor: Palette.panel,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Palette.accent),
        ),
      ),
    );
  }

  Widget _familyRow() {
    return Row(
      children: [
        for (final option in SoundFamily.values) ...[
          Expanded(child: _familyChip(option)),
          if (option != SoundFamily.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _familyChip(SoundFamily option) {
    final selected = option == family;
    return GestureDetector(
      onTap: () => onFamilyChanged(option),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? option.color.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? option.color : Palette.line),
        ),
        child: Text(
          option.label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? option.color : Palette.inkDim,
          ),
        ),
      ),
    );
  }

  Widget _button({
    required String label,
    required VoidCallback onTap,
    required Color background,
    required Color foreground,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: background == Colors.transparent ? Palette.line : background,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      ),
    );
  }
}
