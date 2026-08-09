import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'voice_note.dart';

/// What came out of a recording.
class VoiceRecording {
  VoiceRecording(this.bytes, this.duration);

  final Uint8List bytes;
  final Duration duration;
}

/// The record button and the bar it turns the composer into.
///
/// The gesture is the one people already have in their hands: hold to
/// record, let go to send, slide left to throw it away, slide up to lock so
/// it keeps recording without a finger held down. Every one of those has a
/// visible affordance while it is happening — a hint that says what sliding
/// does, a lock that fills as you approach it — because a gesture nobody is
/// told about is a gesture nobody uses.
///
/// Anything shorter than [_tooShort] is discarded with a word about why.
/// Without that, a mistimed tap sends a quarter-second of nothing, and the
/// only way to take it back is to delete a message.
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
  Duration _elapsed = Duration.zero;
  double _level = 0;
  Offset _drag = Offset.zero;
  Timer? _ticker;

  bool get recording => _recording;
  bool get locked => _locked;
  Duration get elapsed => _elapsed;
  double get level => _level;

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
    final started = await VoiceNotes.instance.start();
    _starting = false;
    if (!mounted) return;
    if (!started) {
      _complain('Microphone permission is needed to record a voice message.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _locked = false;
      _elapsed = Duration.zero;
      _drag = Offset.zero;
    });
    widget.onRecordingChanged(true);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (!mounted || !_recording) return;
      final level = await VoiceNotes.instance.level();
      if (!mounted || !_recording) return;
      setState(() {
        _elapsed += const Duration(milliseconds: 100);
        _level = level;
      });
      widget.onTick();
      // The cap is enforced here rather than refused later, so a long note
      // is sent rather than lost.
      if (_elapsed >= VoiceNotes.maxDuration) await finish();
    });
  }

  /// Stops and sends, unless it was too short to have been meant.
  Future<void> finish() async {
    if (!_recording) return;
    _ticker?.cancel();
    final held = _elapsed;
    setState(() {
      _recording = false;
      _locked = false;
      _drag = Offset.zero;
    });
    widget.onRecordingChanged(false);
    final bytes = await VoiceNotes.instance.stop();
    if (!mounted) return;
    if (held < _tooShort) {
      _complain('Hold the microphone to record.');
      return;
    }
    if (bytes == null) {
      _complain('Nothing was recorded.');
      return;
    }
    HapticFeedback.lightImpact();
    widget.onRecorded(VoiceRecording(bytes, held));
  }

  Future<void> discard() async {
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

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_recording || _locked) return;
    setState(() => _drag += details.delta);
    if (lockProgress >= 1) {
      HapticFeedback.mediumImpact();
      setState(() {
        _locked = true;
        _drag = Offset.zero;
      });
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

    return GestureDetector(
      onLongPressStart: (_) => _begin(),
      onLongPressEnd: (_) => finish(),
      onLongPressMoveUpdate: (details) {
        if (!_recording || _locked) return;
        setState(() => _drag = details.offsetFromOrigin);
        if (lockProgress >= 1) {
          HapticFeedback.mediumImpact();
          setState(() {
            _locked = true;
            _drag = Offset.zero;
          });
        } else if (cancelProgress >= 1) {
          discard();
        }
      },
      onPanUpdate: _onDragUpdate,
      // A plain tap is the commonest mistake here, so it says what to do
      // rather than doing nothing.
      onTap: () => _complain('Hold to record a voice message.'),
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
  });

  final Duration elapsed;
  final double level;
  final bool locked;
  final double cancelProgress;
  final double lockProgress;

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
          Expanded(child: _Meter(level: level)),
          const SizedBox(width: 10),
          if (locked)
            Text(
              'hands free',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The lock fills as the finger rises towards it, which is
                // the only way to discover the gesture exists.
                Opacity(
                  opacity: 0.4 + lockProgress * 0.6,
                  child: Icon(
                    lockProgress > 0.5
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 15,
                  ),
                ),
                const SizedBox(width: 8),
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

/// A live level meter, so the user can see the microphone is working.
class _Meter extends StatelessWidget {
  const _Meter({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var bar = 0; bar < 18; bar++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  // Bars nearer the middle react more, so the shape reads as
                  // a voice rather than a row of equal blocks.
                  height: 3 +
                      level *
                          16 *
                          (1 - (bar - 8.5).abs() / 10).clamp(0.2, 1.0),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
