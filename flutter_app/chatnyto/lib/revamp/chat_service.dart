import 'dart:convert';
import 'dart:math';

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
  bool get isPublicGroup => kind == 'group' && secret.isEmpty;

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
      if (json['t'] == null) return null;
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
///
/// Messaging is asynchronous:
///  * every message (P2P and group) is persisted encrypted at rest, under a
///    key derived from the user's identity;
///  * messages sent while offline wait in an encrypted outbox and are
///    flushed as soon as a broker connects;
///  * a lightweight sync protocol replays missed messages: clients
///    broadcast "sync requests" with the timestamp of the last message
///    they hold, and any online member re-publishes what came after — so
///    someone who connects later still receives what was sent before.
class ChatService extends ChangeNotifier {
  ChatService._();

  static final ChatService instance = ChatService._();

  static const _chatsKey = 'revamp.chats.v1';
  static const _legacyMsgsKeyPrefix = 'revamp.msgs.';
  static const _encMsgsKeyPrefix = 'revamp.msgs.enc.';
  static const _encOutboxKey = 'revamp.outbox.enc';
  static const _maxStoredMessages = 200;
  static const _maxReplayMessages = 50;
  static const _replayCooldown = Duration(minutes: 2);

  final List<ChatEntry> _chats = [];
  final Map<String, List<RevampMessage>> _messages = {};
  final List<Map<String, dynamic>> _outbox = []; // {'chat': id, 'msg': json}
  final Map<String, DateTime> _lastReplyAt = {};
  bool _initialized = false;
  bool _wasConnected = false;

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
    await _loadOutbox();
    final brokers = BrokerService.instance;
    brokers.onChatMessage = _onIncoming;
    brokers.onHeartbeat = _onHeartbeat;
    brokers.addListener(_onBrokersChanged);
    brokers.startHeartbeat();
    notifyListeners();
  }

  // ---------------------------------------------------------------- store

  Future<SecretKey?> get _storageKey => IdentityService.instance.storageKey();

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _chatsKey, _chats.map((c) => jsonEncode(c.toJson())).toList());
  }

  Future<List<RevampMessage>> messagesFor(ChatEntry chat) async {
    if (_messages.containsKey(chat.id)) return _messages[chat.id]!;
    final prefs = await SharedPreferences.getInstance();
    final key = await _storageKey;
    var list = <RevampMessage>[];

    final encrypted = prefs.getString('$_encMsgsKeyPrefix${chat.id}');
    if (encrypted != null && key != null) {
      final clear = await MessageCrypto.decryptEnvelope(encrypted, key);
      if (clear != null) {
        list = (jsonDecode(clear) as List)
            .map((j) => RevampMessage.fromJson(j as Map<String, dynamic>))
            .whereType<RevampMessage>()
            .toList();
      }
    } else {
      // Migrate pre-encryption plaintext history, then store encrypted.
      final legacy = prefs.getStringList('$_legacyMsgsKeyPrefix${chat.id}');
      if (legacy != null) {
        list = legacy
            .map((s) =>
                RevampMessage.fromJson(jsonDecode(s) as Map<String, dynamic>))
            .whereType<RevampMessage>()
            .toList();
        _messages[chat.id] = list;
        await _saveMessages(chat);
        await prefs.remove('$_legacyMsgsKeyPrefix${chat.id}');
      }
    }
    _messages[chat.id] = list;
    return list;
  }

  Future<void> _saveMessages(ChatEntry chat) async {
    final key = await _storageKey;
    if (key == null) return; // locked: keep in memory only
    final prefs = await SharedPreferences.getInstance();
    var list = _messages[chat.id] ?? [];
    if (list.length > _maxStoredMessages) {
      list = list.sublist(list.length - _maxStoredMessages);
      _messages[chat.id] = list;
    }
    final envelope = await MessageCrypto.encryptEnvelope(
        jsonEncode(list.map((m) => m.toJson()).toList()), key);
    await prefs.setString('$_encMsgsKeyPrefix${chat.id}', envelope);
  }

  Future<void> _loadOutbox() async {
    final key = await _storageKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(_encOutboxKey);
    if (encrypted == null) return;
    final clear = await MessageCrypto.decryptEnvelope(encrypted, key);
    if (clear == null) return;
    _outbox
      ..clear()
      ..addAll((jsonDecode(clear) as List)
          .map((j) => Map<String, dynamic>.from(j)));
  }

  Future<void> _saveOutbox() async {
    final key = await _storageKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    final envelope =
        await MessageCrypto.encryptEnvelope(jsonEncode(_outbox), key);
    await prefs.setString(_encOutboxKey, envelope);
  }

  // ---------------------------------------------------------------- chats

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
  /// passphrase, if set) joins the same encrypted room. Public groups
  /// (no passphrase) are advertised on the mesh for discovery.
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
    announcePublicGroups();
    // Ask the mesh for the group's history right away.
    _requestSync(chat);
    notifyListeners();
    return chat;
  }

  Future<void> renameChat(ChatEntry chat, String title) async {
    if (title.trim().isEmpty) return;
    chat.title = title.trim();
    await _saveChats();
    notifyListeners();
  }

  Future<void> removeChat(ChatEntry chat) async {
    _chats.removeWhere((c) => c.id == chat.id);
    _messages.remove(chat.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_encMsgsKeyPrefix${chat.id}');
    await prefs.remove('$_legacyMsgsKeyPrefix${chat.id}');
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

  // ------------------------------------------------------------ messaging

  /// Sends [text] to [chat]. Works offline: the message lands in the chat
  /// immediately and waits in the encrypted outbox until a broker is
  /// reachable.
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
    await _append(chat, message, countUnread: false);
    if (BrokerService.instance.anyConnected) {
      final envelope = await MessageCrypto.encryptEnvelope(
          jsonEncode(message.toJson()), key);
      BrokerService.instance.publishToAll(chat.topic, envelope);
    } else {
      _outbox.add({'chat': chat.id, 'msg': message.toJson()});
      await _saveOutbox();
    }
    return true;
  }

  Future<void> _flushOutbox() async {
    if (_outbox.isEmpty || !BrokerService.instance.anyConnected) return;
    final pending = List<Map<String, dynamic>>.from(_outbox);
    _outbox.clear();
    for (final item in pending) {
      final chat =
          _chats.where((c) => c.id == item['chat']).firstOrNull;
      final message = RevampMessage.fromJson(
          Map<String, dynamic>.from(item['msg']));
      if (chat == null || message == null) continue;
      final key = await _keyFor(chat);
      if (key == null) continue;
      final envelope = await MessageCrypto.encryptEnvelope(
          jsonEncode(message.toJson()), key);
      BrokerService.instance.publishToAll(chat.topic, envelope);
    }
    await _saveOutbox();
  }

  Future<void> _append(ChatEntry chat, RevampMessage message,
      {required bool countUnread}) async {
    final list = await messagesFor(chat);
    final duplicate =
        list.any((m) => m.ts == message.ts && m.from == message.from);
    if (duplicate) return;
    list.add(message);
    list.sort((a, b) => a.ts.compareTo(b.ts));
    if (message.ts >= chat.lastTs) {
      chat.lastMessage = message.text;
      chat.lastTs = message.ts;
    }
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

  // ----------------------------------------------------- sync + discovery

  void _onBrokersChanged() {
    final connected = BrokerService.instance.anyConnected;
    if (connected && !_wasConnected) {
      // Just (re)connected: push queued messages and catch up on history.
      _flushOutbox();
      syncAll();
      announcePublicGroups();
    }
    _wasConnected = connected;
  }

  Future<void> _onHeartbeat() async {
    await _flushOutbox();
    announcePublicGroups();
    await syncAll();
  }

  /// Advertises public (passphrase-less) groups so others can discover
  /// and join them from the People tab.
  void announcePublicGroups() {
    if (!BrokerService.instance.anyConnected) return;
    for (final chat in _chats.where((c) => c.isPublicGroup)) {
      final slug = chat.id.substring('group:'.length);
      BrokerService.instance.publishToAll(
        '$groupsTopicPrefix/$slug',
        jsonEncode({'slug': slug, 'name': chat.title}),
      );
    }
  }

  /// Broadcasts, for every chat, the timestamp of the newest message we
  /// hold; online members reply by re-publishing what we're missing.
  Future<void> syncAll() async {
    if (!BrokerService.instance.anyConnected) return;
    for (final chat in List<ChatEntry>.from(_chats)) {
      await _requestSync(chat);
    }
  }

  Future<void> _requestSync(ChatEntry chat) async {
    final key = await _keyFor(chat);
    if (key == null) return;
    final envelope = await MessageCrypto.encryptEnvelope(
      jsonEncode({'type': 'sync_req', 'since': chat.lastTs}),
      key,
    );
    BrokerService.instance.publishToAll(chat.topic, envelope);
  }

  /// Replays our stored messages newer than [since] so a member who was
  /// offline catches up. Throttled per chat to avoid replay storms.
  Future<void> _replayHistory(ChatEntry chat, int since) async {
    final last = _lastReplyAt[chat.id];
    if (last != null && DateTime.now().difference(last) < _replayCooldown) {
      return;
    }
    final list = await messagesFor(chat);
    final missing = list.where((m) => m.ts > since).toList();
    if (missing.isEmpty) return;
    _lastReplyAt[chat.id] = DateTime.now();
    final key = await _keyFor(chat);
    if (key == null) return;
    // Small random delay so not every member replays at the same instant.
    await Future.delayed(Duration(milliseconds: Random().nextInt(3000)));
    for (final message in missing.take(_maxReplayMessages)) {
      final envelope = await MessageCrypto.encryptEnvelope(
          jsonEncode(message.toJson()), key);
      BrokerService.instance.publishToAll(chat.topic, envelope);
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
    Map<String, dynamic> data;
    try {
      data = jsonDecode(clear) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (data['type'] == 'sync_req') {
      final since = (data['since'] as num?)?.toInt() ?? 0;
      _replayHistory(chat, since);
      return;
    }
    final message = RevampMessage.fromJson(data);
    if (message == null) return;
    String myFp = '';
    if (IdentityService.instance.isUnlocked) {
      myFp = (await IdentityService.instance.publicIdentity()).fingerprint;
    }
    if (message.from == myFp && message.from.isNotEmpty) {
      // Our own message echoed back (broker loopback or replay).
      await _append(chat, message, countUnread: false);
      return;
    }
    await _append(chat, message, countUnread: true);
  }
}
