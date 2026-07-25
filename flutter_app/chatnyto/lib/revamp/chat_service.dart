import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';

/// One conversation: a direct message with a verified person, or a named
/// group. Brokers are invisible here — messages travel over whichever
/// brokers happen to be connected.
class ChatEntry {
  ChatEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.topic,
    this.peer,
    this.secret = '',
    this.lastMessage = '',
    this.lastTs = 0,
    this.unread = 0,
  });

  final String id; // 'dm:<fingerprint>' or 'group:<slug>'
  final String kind; // 'dm' | 'group'
  String title;
  final String topic;
  final Map<String, dynamic>? peer; // PublicIdentity json for DMs
  final String secret; // optional group passphrase
  String lastMessage;
  int lastTs;
  int unread;

  bool get isDm => kind == 'dm';

  PublicIdentity? get peerIdentity =>
      peer == null ? null : PublicIdentity.fromJson(peer!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'topic': topic,
        'peer': peer,
        'secret': secret,
        'last': lastMessage,
        'ts': lastTs,
        'unread': unread,
      };

  static ChatEntry fromJson(Map<String, dynamic> json) => ChatEntry(
        id: json['id'],
        kind: json['kind'],
        title: json['title'],
        topic: json['topic'],
        peer: json['peer'] == null
            ? null
            : Map<String, dynamic>.from(json['peer']),
        secret: json['secret'] ?? '',
        lastMessage: json['last'] ?? '',
        lastTs: (json['ts'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );
}

/// A plain-text chat message (revamp UX keeps messaging simple).
class RevampMessage {
  RevampMessage({
    required this.from,
    required this.name,
    required this.text,
    required this.ts,
  });

  final String from; // sender fingerprint ('' when anonymous)
  final String name;
  final String text;
  final int ts;

  Map<String, dynamic> toJson() =>
      {'f': from, 'n': name, 't': text, 'ts': ts};

  static RevampMessage? fromJson(Map<String, dynamic> json) {
    try {
      return RevampMessage(
        from: json['f'] ?? '',
        name: json['n'] ?? '',
        text: json['t'] ?? '',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  String get timeLabel {
    final time = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final hhmm = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return hhmm;
    }
    return '${time.day}/${time.month} $hhmm';
  }
}

/// Chat list + message routing over the broker abstraction, end-to-end
/// encrypted: DMs use X25519 ECDH with the peer's advertised public key,
/// groups use a key derived from the group name (or its passphrase).
class ChatService extends ChangeNotifier {
  ChatService._();

  static final ChatService instance = ChatService._();

  static const _chatsKey = 'revamp.chats.v1';
  static const _msgsKeyPrefix = 'revamp.msgs.';
  static const _maxStoredMessages = 200;

  final List<ChatEntry> _chats = [];
  final Map<String, List<RevampMessage>> _messages = {};
  bool _initialized = false;

  List<ChatEntry> get chats {
    final sorted = List<ChatEntry>.from(_chats)
      ..sort((a, b) => b.lastTs.compareTo(a.lastTs));
    return sorted;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_chatsKey) ?? [];
    _chats.addAll(stored
        .map((s) => ChatEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    BrokerService.instance.onChatMessage = _onIncoming;
    notifyListeners();
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _chatsKey, _chats.map((c) => jsonEncode(c.toJson())).toList());
  }

  static String _clean(String fingerprint) =>
      fingerprint.replaceAll(':', '');

  static String _dmTopic(String fpA, String fpB) {
    final fps = [_clean(fpA), _clean(fpB)]..sort();
    return '$chatTopicPrefix/dm/${fps[0]}--${fps[1]}';
  }

  /// Opens (or creates) the direct chat with [peer].
  Future<ChatEntry> startDm(PublicIdentity peer) async {
    final id = 'dm:${peer.fingerprint}';
    final existing = _chats.where((c) => c.id == id).firstOrNull;
    if (existing != null) return existing;
    final my = await IdentityService.instance.publicIdentity();
    final chat = ChatEntry(
      id: id,
      kind: 'dm',
      title: peer.name,
      topic: _dmTopic(my.fingerprint, peer.fingerprint),
      peer: peer.toJson(),
    );
    _chats.add(chat);
    await _saveChats();
    notifyListeners();
    return chat;
  }

  /// Creates (or opens) a group chat; anyone entering the same name (and
  /// passphrase, if set) joins the same encrypted room.
  Future<ChatEntry> createGroup(String name, {String secret = ''}) async {
    final slug = name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final id = 'group:$slug';
    final existing = _chats.where((c) => c.id == id).firstOrNull;
    if (existing != null) return existing;
    final chat = ChatEntry(
      id: id,
      kind: 'group',
      title: name.trim(),
      topic: '$chatTopicPrefix/group/$slug',
      secret: secret,
    );
    _chats.add(chat);
    await _saveChats();
    notifyListeners();
    return chat;
  }

  Future<void> removeChat(ChatEntry chat) async {
    _chats.removeWhere((c) => c.id == chat.id);
    _messages.remove(chat.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_msgsKeyPrefix${chat.id}');
    await _saveChats();
    notifyListeners();
  }

  Future<SecretKey?> _keyFor(ChatEntry chat) async {
    if (chat.isDm) {
      final peer = chat.peerIdentity;
      if (peer == null || !IdentityService.instance.isUnlocked) return null;
      return IdentityService.instance.sharedKeyWith(peer);
    }
    return MessageCrypto.deriveChannelKey(chat.secret, chat.topic);
  }

  Future<List<RevampMessage>> messagesFor(ChatEntry chat) async {
    if (_messages.containsKey(chat.id)) return _messages[chat.id]!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_msgsKeyPrefix${chat.id}') ?? [];
    final list = stored
        .map((s) =>
            RevampMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .whereType<RevampMessage>()
        .toList();
    _messages[chat.id] = list;
    return list;
  }

  Future<void> _saveMessages(ChatEntry chat) async {
    final prefs = await SharedPreferences.getInstance();
    var list = _messages[chat.id] ?? [];
    if (list.length > _maxStoredMessages) {
      list = list.sublist(list.length - _maxStoredMessages);
      _messages[chat.id] = list;
    }
    await prefs.setStringList('$_msgsKeyPrefix${chat.id}',
        list.map((m) => jsonEncode(m.toJson())).toList());
  }

  /// Sends [text] to [chat] over every connected broker.
  Future<bool> sendText(ChatEntry chat, String text) async {
    final key = await _keyFor(chat);
    if (key == null) return false;
    String from = '';
    String name = 'me';
    if (IdentityService.instance.isUnlocked) {
      final my = await IdentityService.instance.publicIdentity();
      from = my.fingerprint;
      name = my.name;
    }
    final message = RevampMessage(
      from: from,
      name: name,
      text: text,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    final envelope = await MessageCrypto.encryptEnvelope(
        jsonEncode(message.toJson()), key);
    BrokerService.instance.publishToAll(chat.topic, envelope);
    await _append(chat, message, countUnread: false);
    return true;
  }

  Future<void> _append(ChatEntry chat, RevampMessage message,
      {required bool countUnread}) async {
    final list = await messagesFor(chat);
    final duplicate =
        list.any((m) => m.ts == message.ts && m.from == message.from);
    if (duplicate) return;
    list.add(message);
    chat.lastMessage = message.text;
    chat.lastTs = message.ts;
    if (countUnread) chat.unread += 1;
    await _saveMessages(chat);
    await _saveChats();
    notifyListeners();
  }

  void markRead(ChatEntry chat) {
    if (chat.unread != 0) {
      chat.unread = 0;
      _saveChats();
      notifyListeners();
    }
  }

  Future<void> _onIncoming(String topic, String payload) async {
    var chat = _chats.where((c) => c.topic == topic).firstOrNull;

    // Unknown DM addressed to us: create the chat on the fly so people can
    // reach you without any setup on your side.
    if (chat == null &&
        topic.startsWith('$chatTopicPrefix/dm/') &&
        IdentityService.instance.isUnlocked) {
      final my = await IdentityService.instance.publicIdentity();
      final myClean = _clean(my.fingerprint);
      final pair = topic.substring('$chatTopicPrefix/dm/'.length).split('--');
      if (pair.length == 2 && pair.contains(myClean)) {
        final otherClean = pair.firstWhere((p) => p != myClean,
            orElse: () => '');
        final peer = BrokerService.instance.peers
            .where((p) => _clean(p.fingerprint) == otherClean)
            .firstOrNull;
        if (peer != null) {
          chat = await startDm(peer);
        }
      }
    }
    if (chat == null) return;

    final key = await _keyFor(chat);
    if (key == null) return;
    final clear = await MessageCrypto.decryptEnvelope(payload, key);
    if (clear == null) return;
    RevampMessage? message;
    try {
      message =
          RevampMessage.fromJson(jsonDecode(clear) as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    if (message == null) return;
    String myFp = '';
    if (IdentityService.instance.isUnlocked) {
      myFp = (await IdentityService.instance.publicIdentity()).fingerprint;
    }
    await _append(chat, message, countUnread: message.from != myFp);
  }
}
