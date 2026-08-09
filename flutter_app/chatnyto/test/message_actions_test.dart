import 'dart:convert';

import 'package:chatnyto/revamp/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

RevampMessage _message({
  String from = 'aa:bb',
  int ts = 1700000000000,
  String text = 'hello',
}) =>
    RevampMessage(from: from, name: 'Ada', text: text, ts: ts);

void main() {
  group('naming a message', () {
    test('an id is its sender and the moment they sent it', () {
      expect(_message().id, 'aa:bb-1700000000000');
    });

    test('two messages from the same person are told apart', () {
      expect(_message(ts: 1).id, isNot(_message(ts: 2).id));
    });
  });

  group('taking a message back', () {
    test('its own sender may', () {
      expect(
        ChatService.mayDelete(target: 'aa:bb-1700000000000', by: 'aa:bb'),
        isTrue,
      );
    });

    test('somebody else in the group may not', () {
      // Everyone in a group holds the channel key, so this is the only thing
      // standing between a member and erasing another member's words.
      expect(
        ChatService.mayDelete(target: 'aa:bb-1700000000000', by: 'cc:dd'),
        isFalse,
      );
    });

    test('a fingerprint that is a prefix of the sender may not', () {
      // 'aa' is a prefix of 'aa:bb'. Comparing prefixes without the
      // separator would have let it through.
      expect(
        ChatService.mayDelete(target: 'aa:bb-1700000000000', by: 'aa'),
        isFalse,
      );
    });

    test('an anonymous message cannot be taken back by anyone', () {
      expect(ChatService.mayDelete(target: '-1700000000000', by: ''), isFalse);
      expect(
        ChatService.mayDelete(target: '-1700000000000', by: 'aa:bb'),
        isFalse,
      );
    });
  });

  group('quoting', () {
    test('a long message is quoted short', () {
      // The quote is a copy that travels with every reply, so it is bounded.
      final long = _message(text: 'x' * 500);
      expect(ChatService.quotedPreview(long).length, lessThanOrEqualTo(140));
    });

    test('a picture with no caption still has something to quote', () {
      final photo = RevampMessage(
        from: 'aa:bb',
        name: 'Ada',
        text: '',
        ts: 1,
        image: 'AAAA',
      );
      expect(ChatService.quotedPreview(photo), '📷 Photo');
    });

    test('a message that was taken back quotes as such', () {
      final gone = _message()..deleted = true;
      expect(ChatService.quotedPreview(gone), ChatService.deletedLabel);
    });
  });

  group('what travels and what stays', () {
    test('a reply carries the quote with it', () {
      // A reply has to render as a reply on a device that never received the
      // message it answers, so the quote goes along rather than being
      // looked up.
      final reply = RevampMessage(
        from: 'cc:dd',
        name: 'Bo',
        text: 'agreed',
        ts: 2,
        replyTo: 'aa:bb-1',
        replyName: 'Ada',
        replyText: 'hello',
      );
      final wire = reply.toWire();
      expect(wire['rt'], 'aa:bb-1');
      expect(wire['rn'], 'Ada');
      expect(wire['rx'], 'hello');
      final back = RevampMessage.fromJson(
          jsonDecode(jsonEncode(wire)) as Map<String, dynamic>)!;
      expect(back.isReply, isTrue);
      expect(back.replyText, 'hello');
    });

    test('reactions and stars are not sent with a resent message', () {
      // Reactions arrive in their own envelopes; a star is a private
      // bookmark. Echoing either inside a resend would tell the other end
      // things it has no business knowing, and would fight with the
      // envelopes that are authoritative.
      final message = _message()
        ..reactions['cc:dd'] = '👍'
        ..starred = true;
      final wire = message.toWire();
      expect(wire.containsKey('rcs'), isFalse);
      expect(wire.containsKey('star'), isFalse);
      expect(wire.containsKey('s'), isFalse);
    });

    test('reactions and stars do survive being stored', () {
      final message = _message()
        ..reactions['cc:dd'] = '👍'
        ..starred = true;
      final back = RevampMessage.fromJson(
          jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>)!;
      expect(back.reactions['cc:dd'], '👍');
      expect(back.starred, isTrue);
    });

    test('a tombstone survives a restart', () {
      // Otherwise a message taken back would come back on the next launch.
      final gone = _message()..deleted = true;
      final back = RevampMessage.fromJson(
          jsonDecode(jsonEncode(gone.toJson())) as Map<String, dynamic>)!;
      expect(back.deleted, isTrue);
    });

    test('a forwarded message says so', () {
      final passed = RevampMessage(
          from: 'aa:bb', name: 'Ada', text: 'look', ts: 1, forwarded: true);
      final back = RevampMessage.fromJson(
          jsonDecode(jsonEncode(passed.toWire())) as Map<String, dynamic>)!;
      expect(back.forwarded, isTrue);
    });

    test('a message from an older build has none of this and still reads', () {
      final back = RevampMessage.fromJson({
        'f': 'aa:bb',
        'n': 'Ada',
        't': 'hello',
        'ts': 1,
      })!;
      expect(back.isReply, isFalse);
      expect(back.forwarded, isFalse);
      expect(back.deleted, isFalse);
      expect(back.starred, isFalse);
      expect(back.reactions, isEmpty);
    });
  });
}
