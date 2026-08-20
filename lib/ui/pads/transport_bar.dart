import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';

/// One transport button: icon, tiny caption, and an on/off look.
class TransportAction {
  const TransportAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.recording = false,
    this.onLongPress,
    this.onPressStart,
    this.onPressEnd,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Held controls — the roll — fire on press and stop on release instead of
  /// on a tap, so the rhythm follows the finger.
  final VoidCallback? onPressStart;
  final VoidCallback? onPressEnd;

  final bool active;
  final bool recording;
}

/// The six controls that sit in the thumb's arc. They stay usable while a take
/// is recording — recording is signalled up top, it never takes controls away.
class TransportBar extends StatelessWidget {
  const TransportBar({super.key, required this.actions});

  final List<TransportAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [for (final a in actions) _button(a)],
      ),
    );
  }

  Widget _button(TransportAction action) {
    final Color background;
    final Color foreground;
    if (action.recording) {
      background = Palette.rec;
      foreground = Palette.onAccent;
    } else if (action.active) {
      background = Palette.accent;
      foreground = Palette.ground;
    } else {
      background = Colors.transparent;
      foreground = Palette.inkDim;
    }

    return GestureDetector(
      onTap: action.onTap,
      onLongPress: action.onLongPress,
      onTapDown: action.onPressStart == null ? null : (_) => action.onPressStart!(),
      onTapUp: action.onPressEnd == null ? null : (_) => action.onPressEnd!(),
      onTapCancel: action.onPressEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(
                color: action.recording
                    ? Palette.rec
                    : (action.active ? Palette.accent : Palette.line),
              ),
            ),
            child: Icon(action.icon, size: 17, color: foreground),
          ),
          const SizedBox(height: 3),
          Text(
            action.label.toUpperCase(),
            style: Brand.label(
              6.5,
              width: 75,
              color: action.active || action.recording
                  ? Palette.inkDim
                  : Palette.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
