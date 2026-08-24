import '../core/palette.dart';
import '../domain/knob_scale.dart';
import '../domain/loop_length.dart';
import '../domain/midi_target.dart';
import '../domain/scale.dart';
import 'session_controller.dart';

/// Where a learned control lands.
///
/// It lives apart from the controller — which is long enough already — and
/// only ever touches the same public setters the knobs do, so a control change
/// and a thumb take exactly the same path into the instrument. Anything that
/// needs new plumbing to be moved from the desk needs it from the screen too.
extension MidiControlSurface on SessionController {
  /// Moves [target] to [position] (0..1), the way the knob would.
  ///
  /// Parameters that follow the selected pad do nothing when no pad is
  /// selected. That is the honest answer: the strip is showing the master row
  /// at that moment, so there is no pad volume to move.
  void moveMidiTarget(MidiTarget target, double position) {
    switch (target.param.scope) {
      case MidiScope.master:
        _moveMaster(target.param, position);
      case MidiScope.bus:
        _moveBus(target.param, target.family, position);
      case MidiScope.pad:
        _movePad(target.param, position);
      case MidiScope.scale:
        _moveScale(target.param, position);
    }
    refreshSurface();
  }

  void _moveMaster(MidiParam param, double position) {
    switch (param) {
      case MidiParam.masterVolume:
        fx.volume = position;
      case MidiParam.masterCutoff:
        fx.cutoff = position;
      case MidiParam.masterResonance:
        fx.resonance = position;
      case MidiParam.masterEcho:
        fx.echo = position;
      case MidiParam.masterDrive:
        fx.drive = position;
      default:
        break;
    }
  }

  void _moveBus(MidiParam param, SoundFamily? family, double position) {
    if (family == null) return;
    switch (param) {
      case MidiParam.busCutoff:
        buses.setCutoff(family, position);
      case MidiParam.busResonance:
        buses.setResonance(family, position);
      case MidiParam.busSend:
        buses.setSend(family, position);
      case MidiParam.busDrive:
        buses.setDrive(family, position);
      default:
        break;
    }
  }

  void _movePad(MidiParam param, double position) {
    final slot = selectedSlot;
    if (slot == null) return;
    final pad = padAt(slot);
    if (pad.isEmpty) return;

    final on = knobAsSwitch(position);
    switch (param) {
      case MidiParam.padVolume:
        setPadVolume(slot, position);
      case MidiParam.padPitch:
        setPadSemitones(slot, knobAsSemitones(position));
      case MidiParam.padPan:
        setPadPan(slot, knobAsPan(position));
      case MidiParam.padMute:
        if (on != pad.muted) toggleMute(slot);
      case MidiParam.padSolo:
        if (on != isSoloOn(slot)) toggleSolo(slot);
      case MidiParam.padLoop:
        if (on != isLooping(activeBank, slot)) setPadLooping(slot, on);
      case MidiParam.padSync:
        if (on != pad.synced) setPadSynced(slot, on);
      case MidiParam.padLoopSteps:
        final choices = loopLengthChoices(pad.loopSteps);
        setPadLoopSteps(slot, choices[knobAsIndex(position, choices.length)]);
      default:
        break;
    }
  }

  void _moveScale(MidiParam param, double position) {
    switch (param) {
      case MidiParam.scaleOn:
        final wanted = knobAsSwitch(position);
        if (wanted == isScaleOn) return;
        // Switching the keyboard on needs a pad to take the sound from, and
        // the selected one is the same one the screen would have used.
        final slot = selectedSlot;
        if (wanted && slot == null) return;
        toggleScale(wanted ? slot : null);
      case MidiParam.scaleRoot:
        setScaleRoot(knobAsRoot(position));
      case MidiParam.scaleKind:
        setScale(Scale.values[knobAsIndex(position, Scale.values.length)]);
      case MidiParam.scaleOctave:
        setScaleOctave(kScaleOctaves[
            knobAsIndex(position, kScaleOctaves.length)]);
      default:
        break;
    }
  }
}
