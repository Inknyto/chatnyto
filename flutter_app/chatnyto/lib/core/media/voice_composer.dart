import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'voice_note.dart';
import 'voice_waveform.dart';

/// What came out of a recording.
class VoiceRecording {
  VoiceRecording(this.bytes, this.duration, this.waveform);

  final Uint8List bytes;
  final Duration duration;

  /// The shape of it, one byte a bar, to be sent with the message.
  final Uint8List waveform;
}

/// The record button and the bar it turns the composer into.
///
/// The gesture is the one people already have in their hands: touch to
/// record, let go to send, slide left to throw it away, slide up to lock so
/// it keeps recording without a finger held down. Every one of those has a
/// visible affordance while it is happening — a hint that says what sliding
/// does, a lock that fills as you approach it — because a gesture nobody is
/// told about is a gesture nobody uses.
///
/// It listens to the raw pointer rather than to a long-press recogniser, and
/// that is the whole reason the slides work. A long press is rejected the
/// moment the finger travels more than a touch slop before it is accepted —
/// so pressing the microphone and sliding up in one movement, which is
/// exactly how the gesture is performed, used to start no recording at all.
/// Recording therefore begins on touch down, and anything shorter than
/// [_tooShort] is thrown away with a word about why, so a stray tap costs
/// nothing.
class VoiceComposer extends StatefulWidget {
  const VoiceComposer({
    super.key,
    required this.onRecorded,
    required this.onRecordingChanged,
    required this.onTick,
  });

  /// Called with the finished note. Never called for a cancelled or
  /// too-short recording.
  final ValueChanged<VoiceRecording> onRecorded;

  /// Lets the composer around it swap the text field for the meter.
  final ValueChanged<bool> onRecordingChanged;

  /// Fired as the elapsed time and level change. The strip that draws them
  /// is a sibling, not a child, so it has to be told to repaint.
  final VoidCallback onTick;

  @override
  State<VoiceComposer> createState() => VoiceComposerState();
}

class VoiceComposerState extends State<VoiceComposer> {
  static const _tooShort = Duration(milliseconds: 700);
  static const _cancelSlide = 90.0;
  static const _lockSlide = 60.0;

  bool _recording = false;
  bool _locked = false;
  bool _starting = false;

  /// Set when the finger comes up while the microphone is still being
  /// opened. Opening it crosses a platform channel and takes a moment, and
  /// a quick tap easily beats it — without this the recorder would be left
  /// running with nobody holding it.
  bool _releasedEarly = false;
  bool _cancelledEarly = false;

  Duration _elapsed = Duration.zero;
  double _level = 0;
  Offset _origin = Offset.zero;
  Offset _drag = Offset.zero;
  Timer? _ticker;
  List<double> _samples = const [];

  bool get recording => _recording;
  bool get locked => _locked;
  Duration get elapsed => _elapsed;
  double get level => _level;

  /// The readings so far, for the meter beside the composer.
  List<double> get samples => _samples;

  /// How close the finger is to cancelling or locking, 0..1, for the hints.
  double get cancelProgress =>
      _locked ? 0 : ((-_drag.dx) / _cancelSlide).clamp(0.0, 1.0);
  double get lockProgress =>
      _locked ? 1 : ((-_drag.dy) / _lockSlide).clamp(0.0, 1.0);

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording) VoiceNotes.instance.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    if (_recording || _starting) return;
    _starting = true;
    _releasedEarly = false;
    _cancelledEarly = false;
    final started = await VoiceNotes.instance.start();
    _starting = false;
    if (!mounted) {
      await VoiceNotes.instance.cancel();
      return;
    }
    if (!started) {
      if (!_cancelledEarly) {
        _complain('Microphone permission is needed to record a voice message.');
      }
      return;
    }
    // The finger was already gone before the microphone opened. Whatever it
    // caught is a fraction of a second of nothing.
    if (_releasedEarly || _cancelledEarly) {
      await VoiceNotes.instance.cancel();
      if (mounted && _releasedEarly) _complain('Hold to record a voice note.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _locked = false;
      _elapsed = Duration.zero;
      _drag = Offset.zero;
      _samples = const [];
    });
    widget.onRecordingChanged(true);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!mounted || !_recording) return;
      final level = await VoiceNotes.instance.level();
      if (!mounted || !_recording) return;
      setState(() {
        _elapsed += const Duration(milliseconds: 100);
        _level = level;
        _samples = VoiceNotes.instance.samples;
      });
      widget.onTick();
      // The cap is enforced here rather than refused later, so a long note
      // is sent rather than lost.
      if (_elapsed >= VoiceNotes.maxDuration) await finish();
    });
  }

  /// Stops and sends, unless it was too short to have been meant.
  Future<void> finish() async {
    if (_starting) {
      _releasedEarly = true;
      return;
    }
    if (!_recording) return;
    _ticker?.cancel();
    final held = _elapsed;
    final shape = VoiceNotes.instance.waveform();
    setState(() {
      _recording = false;
      _locked = false;
      _drag = Offset.zero;
    });
    widget.onRecordingChanged(false);
    final bytes = await VoiceNotes.instance.stop();
    if (!mounted) return;
    if (held < _tooShort) {
      _complain('Hold to record a voice note.');
      return;
    }
    if (bytes == null) {
      _complain('Nothing was recorded.');
      return;
    }
    HapticFeedback.lightImpact();
    widget.onRecorded(VoiceRecording(bytes, held, shape));
  }

  Future<void> discard() async {
    if (_starting) {
      _cancelledEarly = true;
      return;
    }
    if (!_recording) return;
    _ticker?.cancel();
    setState(() {
      _recording = false;
      _locked = false;
      _drag = Offset.zero;
    });
    widget.onRecordingChanged(false);
    await VoiceNotes.instance.cancel();
    HapticFeedback.heavyImpact();
  }

  void _complain(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Follows the finger. Measured from where it first touched down rather
  /// than accumulated from deltas, so a slide that overshoots and comes back
  /// un-arms the gesture instead of staying triggered.
  void _onMove(Offset position) {
    if (!_recording || _locked) return;
    setState(() => _drag = position - _origin);
    if (lockProgress >= 1) {
      HapticFeedback.mediumImpact();
      setState(() {
        _locked = true;
        _drag = Offset.zero;
      });
      widget.onTick();
    } else if (cancelProgress >= 1) {
      discard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Locked: the finger has left the button, so it stops being a hold
    // target and becomes the send button for the recording it started.
    if (_locked) {
      return Container(
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: IconButton(
          tooltip: 'Send',
          icon: Icon(Icons.send_rounded, color: scheme.onPrimary),
          onPressed: finish,
        ),
      );
    }

    // Listener, not GestureDetector: see the note on the class. Nothing here
    // enters the gesture arena, so no recogniser above can take the pointer
    // away mid-slide and no slop threshold can reject the press.
    return Listener(
      onPointerDown: (event) {
        _origin = event.position;
        _drag = Offset.zero;
        _begin();
      },
      onPointerMove: (event) => _onMove(event.position),
      // The lock check is not belt and braces. Locking swaps this widget out
      // for the send button, but the framework goes on delivering the rest
      // of that pointer's events to the route it hit on the way down — so
      // without this, sliding up to go hands-free and then lifting the
      // finger would send the note on the spot, which is the opposite of
      // what locking is for.
      onPointerUp: (_) {
        if (!_locked) finish();
      },
      // A pointer the system takes back — a notification pulled down over
      // the app, a call arriving — is not a send.
      onPointerCancel: (_) {
        if (!_locked) discard();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _recording ? Colors.redAccent : scheme.primary,
          shape: BoxShape.circle,
          boxShadow: _recording
              ? [
                  BoxShadow(
                    color: Colors.redAccent.withValues(alpha: 0.4),
                    // The glow follows the microphone level, so you can see
                    // that it is hearing you before you play it back.
                    blurRadius: 8 + _level * 22,
                    spreadRadius: _level * 6,
                  ),
                ]
              : null,
        ),
        padding: EdgeInsets.all(_recording ? 14 : 8),
        child: Icon(
          Icons.mic_rounded,
          color: _recording ? Colors.white : scheme.onPrimary,
          size: _recording ? 26 : 24,
        ),
      ),
    );
  }
}

/// What the composer's text field turns into while a note is recording:
/// the elapsed time, a live level meter, and what the two gestures do.
class VoiceRecordingStrip extends StatelessWidget {
  const VoiceRecordingStrip({
    super.key,
    required this.elapsed,
    required this.level,
    required this.locked,
    required this.cancelProgress,
    required this.lockProgress,
    this.samples = const [],
  });

  final Duration elapsed;
  final double level;
  final bool locked;
  final double cancelProgress;
  final double lockProgress;

  /// The loudness readings so far — the same ones that will be sent with the
  /// note, so what is drawn while recording is what the bubble will show.
  final List<double> samples;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Fades as the finger slides towards cancelling: the recording is
          // visibly going away before it is gone.
          Opacity(
            opacity: 1 - cancelProgress * 0.7,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fiber_manual_record_rounded,
                    color:
                        Colors.redAccent.withValues(alpha: 0.6 + level * 0.4),
                    size: 12),
                const SizedBox(width: 6),
                Text(
                  voiceDurationLabel(elapsed),
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LiveWaveform(
              samples: samples,
              color: scheme.primary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 10),
          if (locked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 14, color: scheme.primary),
                const SizedBox(width: 4),
                Text(
                  'hands free',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The lock rises and fills as the finger goes up towards it,
                // which is the only way to discover the gesture exists.
                Transform.translate(
                  offset: Offset(0, -6 * lockProgress),
                  child: Opacity(
                    opacity: 0.4 + lockProgress * 0.6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.keyboard_arrow_up_rounded, size: 14),
                        Icon(
                          lockProgress > 0.5
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 15,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_left_rounded, size: 16),
                Text(
                  'slide to cancel',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
