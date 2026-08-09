import 'package:chatnyto/calls/group_call_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

StatsReport _report(String type, Map<String, dynamic> values) =>
    StatsReport('id-$type', type, 0, values);

void main() {
  group('deciding who offers', () {
    test('exactly one of a pair offers', () {
      // Both sides learn of each other in the same instant. If both offered,
      // each would end up with two half-built connections and no call.
      const ada = 'aa:11';
      const bo = 'bb:22';
      expect(
        GroupCallService.offersTo(ada, bo) !=
            GroupCallService.offersTo(bo, ada),
        isTrue,
      );
    });

    test('the same answer whichever side is asking', () {
      const ada = 'aa:11';
      const bo = 'bb:22';
      expect(GroupCallService.offersTo(ada, bo), isTrue);
      expect(GroupCallService.offersTo(bo, ada), isFalse);
    });

    test('nobody offers to themselves', () {
      expect(GroupCallService.offersTo('aa:11', 'aa:11'), isFalse);
    });

    test('a whole room agrees on every pair', () {
      // With four people there are six pairs, and every one of them has to
      // have exactly one offerer or the room half-connects.
      const room = ['dd:44', 'aa:11', 'cc:33', 'bb:22'];
      for (final me in room) {
        for (final them in room) {
          if (me == them) continue;
          expect(
            GroupCallService.offersTo(me, them),
            isNot(GroupCallService.offersTo(them, me)),
            reason: '$me and $them disagree about who offers',
          );
        }
      }
    });
  });

  group('finding who is talking', () {
    test('an inbound audio level is read', () {
      final level = GroupCallService.audioLevelOf(
        [
          _report('inbound-rtp', {'kind': 'audio', 'audioLevel': 0.42}),
        ],
        inbound: true,
      );
      expect(level, closeTo(0.42, 0.001));
    });

    test('video entries are not mistaken for voices', () {
      final level = GroupCallService.audioLevelOf(
        [
          _report('inbound-rtp', {'kind': 'video', 'audioLevel': 0.9}),
        ],
        inbound: true,
      );
      expect(level, 0);
    });

    test('our own microphone comes from the media source', () {
      final level = GroupCallService.audioLevelOf(
        [
          _report('inbound-rtp', {'kind': 'audio', 'audioLevel': 0.8}),
          _report('media-source', {'kind': 'audio', 'audioLevel': 0.3}),
        ],
        inbound: false,
      );
      // Reading the inbound entry here would light up our own tile whenever
      // anybody else spoke.
      expect(level, closeTo(0.3, 0.001));
    });

    test('a track entry says whether it is ours or theirs', () {
      // Older libwebrtc reports both directions as `track` entries, told
      // apart only by remoteSource.
      const reports = <Map<String, dynamic>>[
        {'kind': 'audio', 'audioLevel': 0.7, 'remoteSource': true},
        {'kind': 'audio', 'audioLevel': 0.1, 'remoteSource': false},
      ];
      final list = reports.map((v) => _report('track', v)).toList();
      expect(
          GroupCallService.audioLevelOf(list, inbound: true), closeTo(0.7, 0.001));
      expect(GroupCallService.audioLevelOf(list, inbound: false),
          closeTo(0.1, 0.001));
    });

    test('a report with nothing in it is silence, not a crash', () {
      expect(GroupCallService.audioLevelOf([], inbound: true), 0);
      expect(
        GroupCallService.audioLevelOf(
            [_report('inbound-rtp', {'kind': 'audio'})],
            inbound: true),
        0,
      );
    });

    test('a level outside the range is brought back into it', () {
      // Nothing should report above 1, but a tile border driven straight
      // from an unclamped number is not worth the risk.
      expect(
        GroupCallService.audioLevelOf(
          [
            _report('inbound-rtp', {'kind': 'audio', 'audioLevel': 4}),
          ],
          inbound: true,
        ),
        1.0,
      );
    });
  });

  group('the size of a room', () {
    test('a mesh is capped', () {
      // Every participant sends their own audio and video to every other
      // one, so this is a real limit rather than a preference.
      expect(GroupCallService.maxParticipants, lessThanOrEqualTo(8));
      expect(GroupCallService.maxParticipants, greaterThan(2));
    });
  });
}
