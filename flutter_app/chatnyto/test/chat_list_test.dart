import 'dart:convert';

import 'package:chatnyto/revamp/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

ChatEntry _chat(String id,
        {int lastTs = 0, bool pinned = false, bool muted = false}) =>
    ChatEntry(
      id: id,
      kind: 'dm',
      title: id,
      topic: 'chatnyto/chat/dm/$id',
      lastTs: lastTs,
      pinned: pinned,
      muted: muted,
    );

void main() {
  group('the order of the list', () {
    test('the newest conversation is at the top', () {
      final chats = [_chat('old', lastTs: 1), _chat('new', lastTs: 2)]
        ..sort(ChatService.compareChats);
      expect(chats.first.id, 'new');
    });

    test('a pinned chat stays above a newer one', () {
      // The point of pinning: a conversation that has gone quiet holds its
      // place rather than sinking.
      final chats = [
        _chat('busy', lastTs: 900),
        _chat('quiet', lastTs: 1, pinned: true),
      ]..sort(ChatService.compareChats);
      expect(chats.first.id, 'quiet');
    });

    test('pinned chats keep their own order among themselves', () {
      final chats = [
        _chat('older-pin', lastTs: 1, pinned: true),
        _chat('newer-pin', lastTs: 2, pinned: true),
      ]..sort(ChatService.compareChats);
      expect(chats.map((c) => c.id), ['newer-pin', 'older-pin']);
    });
  });

  group('what is remembered about a chat', () {
    test('pinned and muted survive a restart', () {
      final back = ChatEntry.fromJson(jsonDecode(
              jsonEncode(_chat('x', pinned: true, muted: true).toJson()))
          as Map<String, dynamic>);
      expect(back.pinned, isTrue);
      expect(back.muted, isTrue);
    });

    test('a chat stored by an older build is neither', () {
      final back = ChatEntry.fromJson(jsonDecode(
          jsonEncode(_chat('x').toJson())) as Map<String, dynamic>);
      expect(back.pinned, isFalse);
      expect(back.muted, isFalse);
    });
  });
}
