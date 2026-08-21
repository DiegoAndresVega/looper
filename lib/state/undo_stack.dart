import '../core/constants.dart';

/// One step back: the state as it was, and a name for what is being taken
/// back. The name is what lets the app say «Deshecho: vaciar pad» instead of
/// leaving the player to guess what just moved.
class UndoEntry<T> {
  const UndoEntry(this.state, this.label);

  final T state;
  final String label;
}

/// A bounded stack of previous states.
///
/// It stores the state *before* each destructive action rather than the action
/// itself, which is only affordable because [Session] is immutable: a snapshot
/// is a handful of references, not a copy of sixty-four pads and sixteen
/// patterns. That is also why there is no redo — the far more common need is
/// to walk back out of a mistake, and a redo stack would double the state to
/// reason about for a fraction of the benefit.
class UndoStack<T> {
  UndoStack({this.limit = kUndoLimit});

  /// How many steps back are kept. Beyond this the oldest is dropped, because
  /// the one thing worse than a short undo is one that grows without end.
  final int limit;

  final List<UndoEntry<T>> _entries = [];

  bool get canUndo => _entries.isNotEmpty;

  int get depth => _entries.length;

  /// What the next undo would take back, or null when there is nothing.
  String? get topLabel => _entries.isEmpty ? null : _entries.last.label;

  void push(T state, String label) {
    _entries.add(UndoEntry(state, label));
    if (_entries.length > limit) _entries.removeAt(0);
  }

  /// The most recent state, removed from the stack. Null when empty.
  UndoEntry<T>? undo() => _entries.isEmpty ? null : _entries.removeLast();

  void clear() => _entries.clear();
}
