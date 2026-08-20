import 'package:flutter/material.dart';

import '../../core/palette.dart';
import '../../core/type.dart';

/// The four bank tabs. A bank whose loops are still running lights up along
/// its bottom edge, so you never lose track of what is sounding off-screen.
class BankTabs extends StatelessWidget {
  const BankTabs({
    super.key,
    required this.ids,
    required this.labels,
    required this.activeIndex,
    required this.busyBanks,
    required this.onSelect,
  });

  final List<String> ids;
  final List<String> labels;
  final int activeIndex;
  final Set<int> busyBanks;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(ids.length, (i) {
        final active = i == activeIndex;
        final busy = busyBanks.contains(i);
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == ids.length - 1 ? 0 : 5),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 7, 0, 5),
                decoration: BoxDecoration(
                  color: active ? Palette.ink : Palette.panel,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: active ? Palette.ink : Palette.line),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ids[i],
                      style: Brand.title(
                        13,
                        color: active ? Palette.ground : Palette.inkDim,
                      ),
                    ),
                    Text(
                      labels[i].toUpperCase(),
                      style: Brand.label(
                        7,
                        width: 75,
                        color: active
                            ? Palette.ground.withValues(alpha: 0.62)
                            : Palette.inkFaint,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: busy ? Palette.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
