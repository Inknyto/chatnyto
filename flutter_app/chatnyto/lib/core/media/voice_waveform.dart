import 'dart:typed_data';

import 'package:flutter/material.dart';

/// The shape of a voice note, drawn as bars and scrubable.
///
/// The bars are the loudness readings taken while the note was recorded and
/// carried with the message, so both ends draw the same picture — the sender
/// sees what they said, and so does the receiver, without either device
/// decoding the audio to find out.
///
/// A note that arrives without them (an older build, another client) is not
/// given an invented shape. It gets a row of equal bars, which is honest
/// about knowing only the length, and still scrubs.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.bars,
    required this.progress,
    required this.played,
    required this.unplayed,
    this.onSeek,
    this.height = 30,
  });

  /// One byte a bar, 0..255. Null when the note carried no waveform.
  final Uint8List? bars;

  /// How far through the note playback is, 0..1.
  final double progress;

  final Color played;
  final Color unplayed;

  /// Called with 0..1 when the user taps or drags along the bars. Null makes
  /// the waveform a display rather than a control.
  final ValueChanged<double>? onSeek;
  final double height;

  @override
  Widget build(BuildContext context) {
    final painter = _WaveformPainter(
      bars: bars,
      progress: progress.clamp(0.0, 1.0),
      played: played,
      unplayed: unplayed,
    );
    final canvas = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: painter),
    );
    if (onSeek == null) return canvas;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset local) {
          final width = constraints.maxWidth;
          if (width <= 0) return;
          onSeek!((local.dx / width).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seek(details.localPosition),
          onHorizontalDragStart: (details) => seek(details.localPosition),
          onHorizontalDragUpdate: (details) => seek(details.localPosition),
          child: canvas,
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.played,
    required this.unplayed,
  });

  final Uint8List? bars;
  final double progress;
  final Color played;
  final Color unplayed;

  /// Bars are drawn at a fixed width and the count follows from how much room
  /// there is, so a note in a narrow bubble and one in a wide bubble have
  /// bars of the same thickness rather than the same number.
  static const _barWidth = 3.0;
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = _barWidth + _gap;
    final count = (size.width / slot).floor();
    if (count <= 0) return;
    final source = bars;
    final middle = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;

    for (var index = 0; index < count; index++) {
      final position = count == 1 ? 0.0 : index / (count - 1);
      // The stored bars are resampled to however many fit, so the same note
      // keeps its shape at any width.
      final double amplitude;
      if (source == null || source.isEmpty) {
        amplitude = 0.28;
      } else {
        final at = (position * (source.length - 1)).round();
        amplitude = source[at] / 255;
      }
      // Never zero: a silent moment is still part of the note, and a gap in
      // the row reads as a rendering fault rather than as quiet.
      final barHeight = (2.5 + amplitude * (size.height - 4)).clamp(
        2.5,
        size.height,
      );
      final x = index * slot + _barWidth / 2;
      paint
        ..color = position <= progress ? played : unplayed
        ..strokeWidth = _barWidth;
      canvas.drawLine(
        Offset(x, middle - barHeight / 2),
        Offset(x, middle + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.bars != bars ||
      old.played != played ||
      old.unplayed != unplayed;
}

/// The live version, drawn while a note is being recorded: the readings so
/// far, scrolling right to left once there are more of them than fit.
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({super.key, required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: CustomPaint(
          painter: _LivePainter(samples: samples, color: color),
          size: Size.infinite,
        ),
      );
}

class _LivePainter extends CustomPainter {
  _LivePainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const slot = 5.0;
    final count = (size.width / slot).floor();
    if (count <= 0) return;
    // Only the tail is shown. A three-minute note squeezed into a strip
    // would be a grey smear; the last few seconds are what tells the user
    // the microphone is still hearing them.
    final start = samples.length > count ? samples.length - count : 0;
    final middle = size.height / 2;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = color;
    for (var index = start; index < samples.length; index++) {
      final x = (index - start) * slot + 1.5;
      final barHeight = 2.5 + samples[index] * (size.height - 4);
      canvas.drawLine(
        Offset(x, middle - barHeight / 2),
        Offset(x, middle + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.samples.length != samples.length || old.color != color;
}
