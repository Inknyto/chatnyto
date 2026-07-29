import 'package:chatnyto/core/notifications/background_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The handover between the running app and the service's own isolate.
///
/// Every case here is one that fails silently on a real phone: the wrong
/// answer either has both isolates listening — so every message notifies
/// twice — or neither, so calls are missed and there is nothing in a log to
/// say why.
void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1800000000000);
  int agoSeconds(int seconds) =>
      now.millisecondsSinceEpoch - seconds * 1000;

  group('deciding whether the app is gone', () {
    test('a stamp from a moment ago means the app is running', () {
      expect(BackgroundClient.appLooksGone(agoSeconds(0), now), isFalse);
      expect(BackgroundClient.appLooksGone(agoSeconds(10), now), isFalse);
    });

    test('a stamp a little stale is still the app — it may just be busy', () {
      // The app stamps every 10 s, so 30 s is two missed stamps and not yet
      // evidence of anything.
      expect(BackgroundClient.appLooksGone(agoSeconds(30), now), isFalse);
      expect(BackgroundClient.appLooksGone(agoSeconds(39), now), isFalse);
    });

    test('a stamp well past the window means the app has gone', () {
      expect(BackgroundClient.appLooksGone(agoSeconds(41), now), isTrue);
      expect(BackgroundClient.appLooksGone(agoSeconds(600), now), isTrue);
    });

    test('never stamped at all means gone', () {
      // A fresh install, or the service starting after a reboot before the
      // app has ever run.
      expect(BackgroundClient.appLooksGone(0, now), isTrue);
    });

    test('zero is the app saying it is leaving, and is believed at once', () {
      // Written on detach, so a call arriving seconds later still rings
      // rather than waiting out the staleness window.
      expect(BackgroundClient.appLooksGone(0, now), isTrue);
    });

    test('a stamp in the future is treated as fresh, not as ancient', () {
      // Clocks move — time zones, NTP, the user changing it. Subtracting
      // would give a negative age; taking its magnitude would read as
      // enormous and hand listening to the wrong isolate.
      expect(BackgroundClient.appLooksGone(agoSeconds(-60), now), isFalse);
    });
  });

  group('recognising what arrived on a topic', () {
    test('a call envelope is a call', () {
      expect(isCallEnvelope({'type': 'call', 'call': 'offer'}), isTrue);
      expect(isCallEnvelope({'type': 'receipt'}), isFalse);
    });

    test('plumbing is never shown to anyone', () {
      // None of these should ever raise a notification.
      for (final type in ['sync_req', 'receipt', 'group_rename',
          'group_delete', 'group_admins']) {
        expect(isPlumbingEnvelope({'type': type}), isTrue,
            reason: '$type should be treated as plumbing');
      }
    });

    test('an ordinary message is neither', () {
      final message = {'f': 'aa:bb', 'n': 'Ada', 't': 'hello', 'ts': 1};
      expect(isCallEnvelope(message), isFalse);
      expect(isPlumbingEnvelope(message), isFalse);
    });

    test('a body that is not JSON is refused rather than thrown on', () {
      expect(decodeBody('not json at all'), isNull);
      expect(decodeBody('[1,2,3]'), isNull);
      expect(decodeBody('{"type":"call"}'), isNotNull);
    });
  });
}
