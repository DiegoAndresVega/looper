import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';
import '../../domain/scene.dart';

/// The eight scenes, in the strip's place under the grid.
///
/// It borrows Live Loops' rule and nothing else: a scene is a section of the
/// piece — what loops, and which pattern goes with it — and one finger brings
/// the whole section in. Looper's 4×4 is already the pads, so the scenes get
/// two rows of four here instead of a column of the grid.
///
/// Three gestures, one each: a tap launches, a hold saves what is sounding,
/// and ARMED (AJUSTAR) turns the tap into an erase — the same bargain the
/// grid already makes everywhere else in this app.
class SceneStrip extends StatelessWidget {
  const SceneStrip({
    super.key,
    required this.scenes,
    required this.activeScene,
    required this.pendingScene,
    required this.armed,
    required this.onLaunch,
    required this.onCapture,
    required this.onClear,
  });

  final List<Scene> scenes;

  /// The scene that is up, and the one queued for the next bar line.
  final int? activeScene;
  final int? pendingScene;

  /// True while AJUSTAR is lit: the next touch settles rather than plays.
  final bool armed;

  final ValueChanged<int> onLaunch;
  final ValueChanged<int> onCapture;
  final ValueChanged<int> onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: armed ? Palette.accent : Palette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _hint(),
          const SizedBox(height: 8),
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var i = row * 4; i < row * 4 + 4; i++) ...[
                  if (i > row * 4) const SizedBox(width: 6),
                  Expanded(child: _cell(i)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// One line that says what the next touch will do. It changes with the
  /// state rather than listing every gesture at once, because the only one
  /// worth reading is the one about to happen.
  Widget _hint() {
    final (String text, Color color) = switch ((armed, pendingScene)) {
      (true, _) => ('Toca una escena para vaciarla', Palette.accent),
      (false, final int queued) => (
          'Escena ${queued + 1} entra en el compás',
          Palette.rec,
        ),
      _ => ('Toca lanza · mantén guarda lo que suena', Palette.inkFaint),
    };

    return Row(
      children: [
        Text('ESCENAS', style: Brand.label(9, width: 75, weight: 700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Brand.label(8.5, width: 75, color: color),
          ),
        ),
      ],
    );
  }

  Widget _cell(int index) {
    final scene = scenes[index];
    final isActive = activeScene == index;
    final isPending = pendingScene == index;

    final Color border = isPending
        ? Palette.rec
        : isActive
            ? Palette.accent
            : Palette.line;
    final Color fill = isActive && !isPending ? Palette.accent : Colors.transparent;
    final Color ink = isActive && !isPending
        ? Palette.onAccent
        : scene.isEmpty
            ? Palette.inkFaint
            : Palette.ink;

    return GestureDetector(
      // An empty scene still answers to a hold: that is how it stops being
      // empty. Only the launch has nothing to do.
      onTap: armed
          ? () => onClear(index)
          : scene.isEmpty
              ? null
              : () => onLaunch(index),
      onLongPress: armed ? null : () => onCapture(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border, width: isPending ? 1.6 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${index + 1}', style: Brand.readout(15, weight: 700, color: ink)),
            const SizedBox(height: 1),
            Text(
              _subtitle(scene),
              style: Brand.label(
                7,
                width: 75,
                color: isActive && !isPending ? Palette.onAccent : Palette.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// How full the scene is, so capturing over one is never a surprise: a
  /// count of loops, and the pattern that comes with them.
  String _subtitle(Scene scene) {
    if (scene.isEmpty) return 'VACÍA';
    return '${scene.loops.length} · P${scene.pattern + 1}';
  }
}
