import 'dart:typed_data';

import 'package:chatnyto/core/media/voice_note.dart';
import 'package:flutter_test/flutter_test.dart';

/// The waveform is measured while recording and sent with the message, so
/// the two ends draw the same picture. These cover the parts that do not
/// need a microphone: how readings become bars, and how bars survive the
/// wire.
void main() {
  group('on the wire', () {
    test('a waveform survives the round trip', () {
      final bars = Uint8List.fromList([0, 17, 255, 128]);
      final back = VoiceNotes.decodeWaveform(VoiceNotes.encodeWaveform(bars));
      expect(back, equals(bars));
    });

    test('a note without one decodes to nothing, not to an empty picture', () {
      // Notes recorded before waveforms existed carry no `wav` field, and the
      // bubble draws plain bars for them rather than a flat line at zero.
      expect(VoiceNotes.decodeWaveform(null), isNull);
      expect(VoiceNotes.decodeWaveform(''), isNull);
    });

    test('a corrupt waveform is not a crash', () {
      expect(VoiceNotes.decodeWaveform('not base64 at all!!'), isNull);
    });

    test('48 bars cost 64 characters', () {
      // The size is the reason for the bar count: it rides inside the
      // message, over whatever link the message takes.
      final encoded = VoiceNotes.encodeWaveform(
          Uint8List(VoiceNotes.waveformBars));
      expect(encoded.length, 64);
    });
  });

  group('turning readings into bars', () {
    test('a recording that caught nothing is flat, not a crash', () {
      final bars = VoiceNotes.waveformOf(const []);
      expect(bars.length, VoiceNotes.waveformBars);
      expect(bars.every((b) => b == 0), isTrue);
    });

    test('the loudest moment reaches the top', () {
      // Scaled to the note rather than to full scale, so speech recorded at
      // arm's length still looks like speech.
      final bars = VoiceNotes.waveformOf([0.1, 0.4, 0.2]);
      expect(bars.reduce((a, b) => a > b ? a : b), 255);
    });

    test('near-silence is not amplified into a picture of nothing', () {
      // Without a floor on the divisor, a note of room tone would be
      // stretched to full height and look like shouting.
      final bars = VoiceNotes.waveformOf([0.01, 0.02, 0.01]);
      expect(bars.reduce((a, b) => a > b ? a : b), lessThan(40));
    });

    test('a bar is the peak of its slice, not its average', () {
      // Two readings a bar: a loud one next to a silent one must still show
      // as loud, or every syllable is smoothed away.
      final bars = VoiceNotes.waveformOf([1.0, 0.0, 1.0, 0.0], bars: 2);
      expect(bars, equals([255, 255]));
    });

    test('fewer readings than bars still fills the row', () {
      // A note barely a second long has ten readings and forty-eight bars.
      // Every bar must still get a value, or the tail of the picture is a
      // flat line that reads as silence the user never recorded.
      final bars = VoiceNotes.waveformOf([0.5, 0.9]);
      expect(bars.length, VoiceNotes.waveformBars);
      expect(bars.where((b) => b > 0).length, VoiceNotes.waveformBars);
    });
  });
}
