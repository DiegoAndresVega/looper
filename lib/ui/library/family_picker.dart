import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';

/// Which family a sound belongs to, picked by colour. The family is not
/// decoration: it is the colour the pad wears on the grid.
class FamilyPicker extends StatelessWidget {
  const FamilyPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final SoundFamily selected;
  final ValueChanged<SoundFamily> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in SoundFamily.values) ...[
          Expanded(child: _chip(option)),
          if (option != SoundFamily.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _chip(SoundFamily option) {
    final isSelected = option == selected;
    return GestureDetector(
      onTap: () => onChanged(option),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? option.color.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? option.color : Palette.line),
        ),
        child: Text(
          option.label.toUpperCase(),
          overflow: TextOverflow.ellipsis,
          style: Brand.label(
            8.5,
            width: 75,
            weight: 700,
            color: isSelected ? option.color : Palette.inkDim,
          ),
        ),
      ),
    );
  }
}
