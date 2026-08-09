import 'package:chatnyto/core/media/voice_note.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voice notes are cached on disk under their sender and timestamp, and the
/// sender is a fingerprint — which is written with colons.
void main() {
  group('naming the file a note is cached in', () {
    test('colons are stripped', () {
      // Android's MediaPlayer refuses a path containing a colon outright,
      // and reports MEDIA_ERROR_UNKNOWN, so every note played silently.
      expect(
        VoiceNotes.fileSafe('9c:4e:e0:5e:53:bb:28:21-1786259835294'),
        '9c4ee05e53bb2821-1786259835294',
      );
    });

    test('nothing that could climb out of the cache directory survives', () {
      expect(VoiceNotes.fileSafe('../../etc/passwd'), 'etcpasswd');
      expect(VoiceNotes.fileSafe('a/b\\c'), 'abc');
    });

    test('ordinary ids are left alone', () {
      expect(VoiceNotes.fileSafe('abc-123_XY'), 'abc-123_XY');
    });
  });

  group('the duration label', () {
    test('is minutes and padded seconds', () {
      expect(voiceDurationLabel(const Duration(seconds: 7)), '0:07');
      expect(voiceDurationLabel(const Duration(seconds: 70)), '1:10');
      expect(voiceDurationLabel(Duration.zero), '0:00');
    });
  });

  group('decoding an attachment', () {
    test('a note with no audio is not a voice note', () {
      expect(VoiceNotes.decode(null), isNull);
      expect(VoiceNotes.decode(''), isNull);
    });

    test('rubbish is refused rather than thrown on', () {
      expect(VoiceNotes.decode('not base64 !!!'), isNull);
    });

    test('base64 comes back as the bytes that went in', () {
      // AAAB in base64 is 0x00 0x00 0x01.
      expect(VoiceNotes.decode('AAAB'), [0, 0, 1]);
    });
  });
}
