import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/palette.dart';
import '../../core/type.dart';

/// One track of the pattern, as this sheet needs to show it.
class TrackRow {
  const TrackRow({
    required this.note,
    required this.label,
    required this.color,
    required this.length,
  });

  /// The pad key the pattern is written in.
  final String note;

  /// What the pad says on screen, so the row is read the same way the grid is.
  final String label;
  final Color color;

  /// How many steps this track runs before it starts over.
  final int length;
}

/// How long each track of the pattern runs.
///
/// Sixteen steps for everybody is a bar; anything else is polymeter. A hat set
/// to seven plays its first seven steps over and over while the kick keeps to
/// the bar, and the two take seven bars to line up again — which is the whole
/// reason a pattern stops sounding like a loop.
///
/// The notes do not move: only the wrap does. A track shortened to seven still
/// has whatever was written on steps eight to sixteen, and getting it back is
/// putting the length back.
class TracksSheet extends StatelessWidget {
  const TracksSheet({
    super.key,
    required this.patternNumber,
    required this.tracks,
    required this.onLength,
  });

  final int patternNumber;
  final List<TrackRow> tracks;
  final void Function(String note, int length) onLength;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.86,
      minChildSize: 0.35,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Palette.ground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _header(),
            const SizedBox(height: 16),
            if (tracks.isEmpty) _empty() else ...tracks.map(_row),
          ],
        ),
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LARGO DE CADA PISTA · P$patternNumber',
                    style: Brand.label(9, weight: 700)),
                const SizedBox(height: 5),
                Text('Polimetría', style: Brand.title(20)),
              ],
            ),
          ),
        ],
      );

  Widget _empty() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.line),
        ),
        child: Text(
          'Este patrón está vacío. Escribe algo primero: las pistas son los '
          'pads que suenan en él.',
          style: Brand.body(12, color: Palette.inkDim),
        ),
      );

  Widget _row(TrackRow track) {
    final full = track.length >= kPatternSteps;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: full ? Palette.line : track.color),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: track.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                track.label,
                overflow: TextOverflow.ellipsis,
                style: Brand.strong(13),
              ),
            ),
            _step(Icons.remove, track.length > 1,
                () => onLength(track.note, track.length - 1)),
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(
                    '${track.length}',
                    textAlign: TextAlign.center,
                    style: Brand.readout(14, weight: 700),
                  ),
                  Text(
                    full ? 'UN COMPÁS' : 'PASOS',
                    textAlign: TextAlign.center,
                    style: Brand.label(6.5, width: 75, color: Palette.inkFaint),
                  ),
                ],
              ),
            ),
            _step(Icons.add, track.length < kPatternSteps,
                () => onLength(track.note, track.length + 1)),
          ],
        ),
      ),
    );
  }

  Widget _step(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Palette.line),
        ),
        child: Icon(
          icon,
          size: 15,
          color: enabled ? Palette.ink : Palette.inkFaint,
        ),
      ),
    );
  }
}
