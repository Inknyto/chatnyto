import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/notifications/background_client.dart';
import '../core/notifications/notification_service.dart';

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
    this.creatorKey = '',
    List<String>? admins,
    this.lastMessage = '',
    this.lastTs = 0,
    this.unread = 0,
    this.lastFromMe = false,
    this.lastStatus,
  }) : admins = admins ?? [];

  String id; // 'dm:<fingerprint>' or 'group:<slug>'
  final String kind; // 'dm' | 'group'
  String title;

  /// MQTT topic the conversation travels on. Renaming a group changes it,
  /// which is why it is not final.
  String topic;
  final Map<String, dynamic>? peer; // PublicIdentity json for DMs
  final String secret; // optional group passphrase

  /// Base64 Ed25519 public key of the group's creator. Only messages signed
  /// with the matching private key may rename or delete the group, or
  /// change who else can.
  String creatorKey;

  /// Base64 Ed25519 public keys the creator designated as admins. They can
  /// rename and delete the group too, but not change this list.
  List<String> admins;

  String lastMessage;
  int lastTs;
  int unread;

  /// Whether the newest message in the conversation is one of ours, and how
  /// far it got — so the chat list can show the same tick as the bubble,
  /// which is the whole point of having it there.
  bool lastFromMe;
  MessageStatus? lastStatus;

  bool get isDm => kind == 'dm';
  bool get isPublicGroup => kind == 'group' && secret.isEmpty;

  String get slug =>
      id.startsWith('group:') ? id.substring('group:'.length) : '';

  PublicIdentity? get peerIdentity =>
      peer == null ? null : PublicIdentity.fromJson(peer!);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'topic': topic,
        'peer': peer,
        'secret': secret,
        'creator': creatorKey,
        'admins': admins,
        'last': lastMessage,
        'ts': lastTs,
        'unread': unread,
        'mine': lastFromMe,
        if (lastStatus != null) 'lastStatus': lastStatus!.name,
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
        creatorKey: json['creator'] ?? '',
        admins: json['admins'] == null
            ? null
            : List<String>.from(json['admins']),
        lastMessage: json['last'] ?? '',
        lastTs: (json['ts'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
        lastFromMe: json['mine'] as bool? ?? false,
        lastStatus: MessageStatus.values
            .where((s) => s.name == json['lastStatus'])
            .firstOrNull,
      );
}

/// How far one of your own messages has got.
///
/// Only meaningful for messages you sent: nobody reports back on what you
/// received. The steps are the honest ones the app can actually observe —
/// waiting for a network, handed to a broker, acknowledged by the other
/// device, and opened by the person.
enum MessageStatus {
  /// Written while offline; sitting in the outbox.
  pending,

  /// Published to at least one broker.
  sent,

  /// The other device has it and said so.
  delivered,

  /// The other person has opened the conversation since it arrived.
  read,
}

/// A chat message. [text] is always the plain-text form (used for previews
/// and for clients that don't render rich text); [delta] carries the Quill
/// document when the message was written with formatting.
class RevampMessage {
  RevampMessage({
    required this.from,
    required this.name,
    required this.text,
    required this.ts,
    this.delta,
    this.image,
    this.audio,
    this.audioMs = 0,
    this.status = MessageStatus.sent,
  });

  final String from; // sender fingerprint ('' when anonymous)
  final String name;
  final String text;
  final int ts;
  final List<dynamic>? delta; // Quill delta operations, when formatted
  final String? image; // base64 JPEG attachment

  /// base64 AAC voice note. Sent as an attachment on an ordinary message so
  /// it inherits the encryption, the chunking and the receipts.
  final String? audio;

  /// How long the note runs. Carried explicitly because the length is what
  /// the bubble shows before anything is decoded or played, and reading it
  /// out of the container would mean decoding every note in a conversation
  /// just to draw the list.
  final int audioMs;

  /// Changes as receipts come back, so it is not final. Never sent over the
  /// wire: it is what *this* device knows about a message's progress, and
  /// the other end has its own view.
  MessageStatus status;

  bool get isRich => delta != null && delta!.isNotEmpty;
  bool get hasImage => image != null && image!.isNotEmpty;
  bool get hasAudio => audio != null && audio!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'f': from,
        'n': name,
        't': text,
        'ts': ts,
        if (isRich) 'd': delta,
        if (hasImage) 'img': image,
        if (hasAudio) 'aud': audio,
        if (hasAudio) 'ams': audioMs,
        // Stored so the ticks survive a restart.
        's': status.name,
      };

  /// What actually goes over the wire. The status is left out on purpose:
  /// it is one device's account of a message's progress, and telling the
  /// other end "this is delivered" before it has it would be nonsense.
  Map<String, dynamic> toWire() => toJson()..remove('s');

  static RevampMessage? fromJson(Map<String, dynamic> json) {
    try {
      if (json['t'] == null) return null;
      return RevampMessage(
        from: json['f'] ?? '',
        name: json['n'] ?? '',
        text: json['t'] ?? '',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
        delta: json['d'] == null ? null : List<dynamic>.from(json['d']),
        image: json['img'] as String?,
        audio: json['aud'] as String?,
        audioMs: (json['ams'] as num?)?.toInt() ?? 0,
        status: MessageStatus.values.firstWhere(
          (s) => s.name == json['s'],
          orElse: () => MessageStatus.sent,
        ),
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

  // Each account keeps its own chats, history and outbox. The suffix is the
  // account's scope, empty for the first account on the device so its data
  // stays exactly where earlier builds put it.
  String get _chatsKey => 'revamp.chats.v1${IdentityService.instance.scope}';
  String get _legacyMsgsKeyPrefix => 'revamp.msgs.';
  String get _encMsgsKeyPrefix =>
      'revamp.msgs.enc${IdentityService.instance.scope}.';
  String get _encOutboxKey =>
      'revamp.outbox.enc${IdentityService.instance.scope}';
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

  /// Forgets everything held for the account that was in use, so switching
  /// identity starts from that account's own storage rather than showing
  /// the previous one's chat list.
  void reset() {
    _chats.clear();
    _messages.clear();
    _outbox.clear();
    _lastReplyAt.clear();
    _keyCache.clear();
    _pendingReceipts.clear();
    _receiptTimer?.cancel();
    _receiptTimer = null;
    _myFingerprint = null;
    _initialized = false;
    notifyListeners();
  }

  /// This account's fingerprint. [IdentityService.publicIdentity] re-signs
  /// the whole advertisement every time it is asked, which is fine once per
  /// message and far too much for every frame of a relayed call.
  String? _myFingerprint;

  Future<String> _fingerprint() async {
    if (_myFingerprint != null) return _myFingerprint!;
    if (!IdentityService.instance.isUnlocked) return '';
    return _myFingerprint =
        (await IdentityService.instance.publicIdentity()).fingerprint;
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

  static String _slugify(String name) => name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Creates (or opens) a group chat; anyone entering the same name (and
  /// passphrase, if set) joins the same encrypted room. Public groups
  /// (no passphrase) are advertised on the mesh for discovery.
  ///
  /// [creatorKey] is the Ed25519 public key of the group's owner: our own
  /// when we create the group, the advertised one when we join a group
  /// discovered on the mesh. Only that key may later rename or delete it.
  Future<ChatEntry> createGroup(
    String name, {
    String secret = '',
    String? creatorKey,
  }) async {
    final slug = _slugify(name);
    final id = 'group:$slug';
    final existing = _chats.where((c) => c.id == id).firstOrNull;
    if (existing != null) return existing;
    var owner = creatorKey ?? '';
    if (creatorKey == null && IdentityService.instance.isUnlocked) {
      owner = await IdentityService.instance.ed25519PublicKeyB64();
    }
    final chat = ChatEntry(
      id: id,
      kind: 'group',
      title: name.trim(),
      topic: '$chatTopicPrefix/group/$slug',
      secret: secret,
      creatorKey: owner,
    );
    _chats.add(chat);
    await _saveChats();
    announcePublicGroups();
    // Ask the mesh for the group's history right away.
    _requestSync(chat);
    notifyListeners();
    return chat;
  }

  /// Joins a group discovered on the mesh, recording its advertised owner.
  Future<ChatEntry> joinPublicGroup(PublicGroupAd ad) =>
      createGroup(ad.name, creatorKey: ad.creatorKey);

  /// True when this device holds the key the group was created with. Only
  /// the creator may appoint admins.
  Future<bool> isGroupOwner(ChatEntry chat) async {
    if (chat.isDm || chat.creatorKey.isEmpty) return false;
    if (!IdentityService.instance.isUnlocked) return false;
    return await IdentityService.instance.ed25519PublicKeyB64() ==
        chat.creatorKey;
  }

  /// True for the creator and for anyone the creator made an admin — the
  /// people allowed to rename the group or delete it for everyone.
  Future<bool> canAdministerGroup(ChatEntry chat) async {
    if (chat.isDm || chat.creatorKey.isEmpty) return false;
    if (!IdentityService.instance.isUnlocked) return false;
    final mine = await IdentityService.instance.ed25519PublicKeyB64();
    return mine == chat.creatorKey || chat.admins.contains(mine);
  }

  /// Replaces the group's admin list and tells the members. Creator only.
  Future<String?> setGroupAdmins(ChatEntry chat, List<String> admins) async {
    if (!await isGroupOwner(chat)) {
      return 'Only the person who created this group can choose its admins.';
    }
    chat.admins = List<String>.from(admins);
    await _saveChats();
    await _publishGroupControl(
      topic: chat.topic,
      secret: chat.secret,
      type: 'group_admins',
      extra: {'admins': chat.admins},
      canonical: 'group_admins:${chat.slug}:${chat.admins.join(',')}',
    );
    notifyListeners();
    return null;
  }

  /// Renames a chat. For a DM the title is a local label, so it just
  /// changes here. For a group the name defines the topic, so renaming
  /// moves the conversation to a new topic and tells the members — and
  /// only the creator may do it.
  Future<String?> renameChat(ChatEntry chat, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return 'Please enter a name.';
    if (chat.isDm) {
      chat.title = trimmed;
      await _saveChats();
      notifyListeners();
      return null;
    }
    if (!await canAdministerGroup(chat)) {
      return 'Only the creator or an admin of this group can rename it.';
    }
    final newSlug = _slugify(trimmed);
    if (newSlug.isEmpty) return 'That name cannot be used.';
    if (newSlug != chat.slug && _chats.any((c) => c.id == 'group:$newSlug')) {
      return 'You already have a group with that name.';
    }
    final oldSlug = chat.slug;
    final oldTopic = chat.topic;

    if (newSlug != oldSlug) {
      // Tell the members on the topic they are still listening on, before
      // moving over: the payload is encrypted with the old channel key and
      // signed with the creator key they recorded when they joined.
      await _publishGroupControl(
        topic: oldTopic,
        secret: chat.secret,
        type: 'group_rename',
        extra: {'slug': newSlug, 'name': trimmed},
        canonical: 'group_rename:$oldSlug:$newSlug:$trimmed',
      );
      await _moveChatStorage(chat, 'group:$newSlug');
      chat.topic = '$chatTopicPrefix/group/$newSlug';
      // Withdraw the old public announcement so nobody joins the dead name.
      if (chat.isPublicGroup) BrokerService.instance.clearGroupAd(oldSlug);
    }
    chat.title = trimmed;
    await _saveChats();
    announcePublicGroups();
    notifyListeners();
    return null;
  }

  /// Deletes a group for everyone. Only the creator can do this; members
  /// receive a signed instruction and drop the conversation.
  Future<String?> deleteGroupForEveryone(ChatEntry chat) async {
    if (chat.isDm) return 'This is not a group.';
    if (!await canAdministerGroup(chat)) {
      return 'Only the creator or an admin of this group can delete it for '
          'everyone.';
    }
    await _publishGroupControl(
      topic: chat.topic,
      secret: chat.secret,
      type: 'group_delete',
      extra: const {},
      canonical: 'group_delete:${chat.slug}',
    );
    if (chat.isPublicGroup) BrokerService.instance.clearGroupAd(chat.slug);
    await removeChat(chat);
    return null;
  }

  /// Publishes a signed, encrypted control message on a group topic.
  Future<void> _publishGroupControl({
    required String topic,
    required String secret,
    required String type,
    required Map<String, dynamic> extra,
    required String canonical,
  }) async {
    if (!IdentityService.instance.isUnlocked) return;
    final key = await MessageCrypto.deriveChannelKey(secret, topic);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final message = '$canonical:$ts';
    final envelope = await MessageCrypto.encryptEnvelope(
      jsonEncode({
        'type': type,
        ...extra,
        'ts': ts,
        'by': await IdentityService.instance.ed25519PublicKeyB64(),
        'sig': await IdentityService.instance.signPayload(message),
      }),
      key,
    );
    BrokerService.instance.publishToAll(topic, envelope);
  }

  /// Moves a chat's stored history to a new id (used when a group rename
  /// changes its topic).
  /// Moves a group's stored history to a new id. Its key is derived from
  /// the topic, and the topic is about to change, so the cached one goes.
  Future<void> _moveChatStorage(ChatEntry chat, String newId) async {
    final oldId = chat.id;
    if (oldId == newId) return;
    _keyCache.remove(oldId);
    _keyCache.remove(newId);
    final messages = await messagesFor(chat);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_encMsgsKeyPrefix$oldId');
    await prefs.remove('$_legacyMsgsKeyPrefix$oldId');
    _messages.remove(oldId);
    for (final item in _outbox) {
      if (item['chat'] == oldId) item['chat'] = newId;
    }
    chat.id = newId;
    _messages[newId] = messages;
    await _saveMessages(chat);
    await _saveOutbox();
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

  /// Channel keys are expensive to derive — an X25519 agreement for a direct
  /// chat, 60 000 rounds of PBKDF2 for a group — and are needed for every
  /// message that arrives on any topic, several times a second while a call
  /// is being relayed. They depend only on the chat and the unlocked
  /// identity, so they are worked out once and kept for as long as both hold.
  final Map<String, SecretKey> _keyCache = {};

  Future<SecretKey?> _keyFor(ChatEntry chat) async {
    final cached = _keyCache[chat.id];
    if (cached != null) return cached;
    SecretKey key;
    if (chat.isDm) {
      final peer = chat.peerIdentity;
      if (peer == null || !IdentityService.instance.isUnlocked) return null;
      key = await IdentityService.instance.sharedKeyWith(peer);
    } else {
      key = await MessageCrypto.deriveChannelKey(chat.secret, chat.topic);
    }
    _keyCache[chat.id] = key;
    return key;
  }

  // ------------------------------------------------------------ messaging

  /// Sends [text] to [chat], optionally with Quill formatting in [delta].
  /// Works offline: the message lands in the chat immediately and waits in
  /// the encrypted outbox until a broker is reachable.
  Future<bool> sendText(ChatEntry chat, String text,
      {List<dynamic>? delta,
      String? image,
      String? audio,
      int audioMs = 0}) async {
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
      delta: delta,
      image: image,
      audio: audio,
      audioMs: audioMs,
      status: BrokerService.instance.anyConnected
          ? MessageStatus.sent
          : MessageStatus.pending,
    );
    await _append(chat, message, countUnread: false);
    if (BrokerService.instance.anyConnected) {
      final envelope = await MessageCrypto.encryptEnvelope(
          jsonEncode(message.toWire()), key);
      BrokerService.instance.publishToAll(chat.topic, envelope);
    } else {
      _outbox.add({'chat': chat.id, 'msg': message.toWire()});
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
          jsonEncode(message.toWire()), key);
      BrokerService.instance.publishToAll(chat.topic, envelope);
      // It has left the device: one tick instead of the clock.
      await _setStatus(chat, message.ts, MessageStatus.sent);
    }
    await _saveOutbox();
  }

  // ------------------------------------------------------------- receipts

  /// Moves one of our own messages forward, never backward: a delivery
  /// receipt arriving after a read receipt (they cross, on a slow link)
  /// must not un-read the message.
  Future<void> _setStatus(
      ChatEntry chat, int ts, MessageStatus status) async {
    final list = _messages[chat.id];
    if (list == null) return;
    var changed = false;
    for (final message in list) {
      if (message.ts != ts) continue;
      if (message.status.index >= status.index) continue;
      message.status = status;
      changed = true;
    }
    if (!changed) return;
    if (ts == chat.lastTs && chat.lastFromMe) {
      chat.lastStatus = status;
      await _saveChats();
    }
    await _saveMessages(chat);
    notifyListeners();
  }

  /// Queues a "got it" for [ts], and sends what has piled up shortly after.
  ///
  /// Catching up after being offline delivers a whole conversation at once,
  /// and a separate publish for each message would answer a burst with a
  /// burst. One receipt listing all of them says exactly the same thing.
  void _acknowledge(ChatEntry chat, int ts) {
    _pendingReceipts.putIfAbsent(chat.id, () => <int>{}).add(ts);
    _receiptTimer ??= Timer(const Duration(milliseconds: 600), () {
      _receiptTimer = null;
      final batches = Map<String, Set<int>>.from(_pendingReceipts);
      _pendingReceipts.clear();
      for (final entry in batches.entries) {
        final chat = _chats.where((c) => c.id == entry.key).firstOrNull;
        if (chat == null) continue;
        _sendReceipt(chat, entry.value.toList(), MessageStatus.delivered);
      }
    });
  }

  final Map<String, Set<int>> _pendingReceipts = {};
  Timer? _receiptTimer;

  /// Tells the sender what happened to their messages.
  ///
  /// Only for direct chats. In a group there is no single answer — "read"
  /// by whom, out of how many? — and two ticks that mean "somebody, maybe"
  /// would be worse than no ticks at all.
  Future<void> _sendReceipt(
      ChatEntry chat, List<int> stamps, MessageStatus status) async {
    if (!chat.isDm || stamps.isEmpty) return;
    final key = await _keyFor(chat);
    if (key == null) return;
    final envelope = await MessageCrypto.encryptEnvelope(
      jsonEncode({
        'type': 'receipt',
        'st': status.name,
        'ts': stamps,
        'from': await _fingerprint(),
      }),
      key,
    );
    BrokerService.instance.publishToAll(chat.topic, envelope);
  }

  Future<void> _applyReceipt(
      ChatEntry chat, Map<String, dynamic> data) async {
    if (data['from'] == await _fingerprint()) return;
    final status = MessageStatus.values
        .where((s) => s.name == data['st'])
        .firstOrNull;
    if (status == null) return;
    final stamps = (data['ts'] as List?)?.whereType<num>() ?? const [];
    if (stamps.isEmpty) return;

    // Deliberately not loading the history to apply this. Decrypting a
    // conversation's whole stored blob — which for a chat with pictures in
    // it is megabytes — on the arrival of every receipt is enough work to
    // stall the interface. A chat that is not open only needs its preview
    // tick to be right; the rest is caught up the moment it is opened.
    if (!_messages.containsKey(chat.id)) {
      if (chat.lastFromMe &&
          stamps.any((s) => s.toInt() == chat.lastTs) &&
          (chat.lastStatus?.index ?? -1) < status.index) {
        chat.lastStatus = status;
        await _saveChats();
        notifyListeners();
      }
      return;
    }
    for (final stamp in stamps) {
      await _setStatus(chat, stamp.toInt(), status);
    }
  }

  /// Adds [message] to the chat; returns false when it was a duplicate
  /// (echo or replay) and nothing changed.
  Future<bool> _append(ChatEntry chat, RevampMessage message,
      {required bool countUnread}) async {
    final list = await messagesFor(chat);
    final duplicate =
        list.any((m) => m.ts == message.ts && m.from == message.from);
    if (duplicate) return false;
    list.add(message);
    list.sort((a, b) => a.ts.compareTo(b.ts));
    if (message.ts >= chat.lastTs) {
      chat.lastMessage = message.text;
      chat.lastTs = message.ts;
      chat.lastFromMe =
          message.from.isNotEmpty && message.from == await _fingerprint();
      chat.lastStatus = chat.lastFromMe ? message.status : null;
    }
    if (countUnread) chat.unread += 1;
    await _saveMessages(chat);
    await _saveChats();
    notifyListeners();
    return true;
  }

  /// Opening a conversation is what "read" means here — the messages are on
  /// screen. The other side is told so their ticks can turn blue.
  Future<void> markRead(ChatEntry chat) async {
    final me = await _fingerprint();
    final theirs = (await messagesFor(chat))
        .where((m) => m.from.isNotEmpty && m.from != me)
        .map((m) => m.ts)
        .toList();
    await _sendReceipt(chat, theirs, MessageStatus.read);
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
      BrokerService.instance.publishToAll(
        '$groupsTopicPrefix/${chat.slug}',
        jsonEncode({
          'slug': chat.slug,
          'name': chat.title,
          'creator': chat.creatorKey,
        }),
        // Retained, so someone joining the network later still discovers
        // the group without waiting for the next heartbeat.
        retain: true,
      );
    }
  }

  /// Set by the call service; receives call signalling that arrived inside
  /// an encrypted direct message.
  Future<void> Function(ChatEntry chat, Map<String, dynamic> data)?
      onCallSignal;

  /// Sends call signalling (ring, answer, ICE, hang up) over [chat]'s
  /// end-to-end encrypted channel. Never queued in the outbox: a call is
  /// only meaningful while both sides are online.
  Future<void> sendCallSignal(
      ChatEntry chat, Map<String, dynamic> data) async {
    final key = await _keyFor(chat);
    if (key == null) return;
    // `type` is written last on purpose: the payload carries keys of its own
    // and must never be able to overwrite the envelope's kind, or the other
    // side files the signal away as a chat message and the phone never rings.
    //
    // `from` is what lets the other end — and this end — tell whose signal it
    // is. The broker delivers our own publications straight back to us, so
    // without it a device answers its own ring.
    final me = IdentityService.instance.isUnlocked
        ? (await IdentityService.instance.publicIdentity()).fingerprint
        : '';
    final envelope = await MessageCrypto.encryptEnvelope(
        jsonEncode({...data, 'type': 'call', 'from': me}), key);
    BrokerService.instance.publishToAll(chat.topic, envelope);
  }

  /// A frame of relayed call audio, encrypted like everything else on this
  /// channel — the broker forwards voice it cannot listen to any more than
  /// it can read the messages.
  ///
  /// Sent at best effort: a frame that misses its moment is worth less than
  /// nothing, so nothing is queued, retried, or written down. The sender's
  /// fingerprint rides along because the broker echoes our own publications
  /// back to us, and a device must not play its own voice.
  Future<void> sendVoiceFrame(ChatEntry chat, List<int> frame) async {
    final key = await _keyFor(chat);
    if (key == null) return;
    final envelope = await MessageCrypto.encryptEnvelope(
      jsonEncode({
        'type': 'call',
        'call': 'voice',
        'from': await _fingerprint(),
        'f': base64Encode(frame),
      }),
      key,
    );
    BrokerService.instance.publishToAll(chat.topic, envelope);
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

  /// Reads something off the wire without changing anything.
  ///
  /// Used by the service's own isolate, which listens while the app is
  /// closed. It shares this method rather than a copy of the decryption so
  /// the two can never disagree about what a ring looks like — but it stops
  /// short of [_append]: nothing is stored, no chat is created, no receipt
  /// is sent. Two isolates writing the same preferences file is how history
  /// gets lost, and the app's sync protocol collects whatever was missed the
  /// moment it opens.
  Future<BackgroundRead?> readForBackground(
      String topic, String payload) async {
    if (!_initialized) {
      // Chats are needed to know which topic belongs to whom, but only read.
      final prefs = await SharedPreferences.getInstance();
      if (_chats.isEmpty) {
        _chats.addAll((prefs.getStringList(_chatsKey) ?? []).map(
            (s) => ChatEntry.fromJson(jsonDecode(s) as Map<String, dynamic>)));
      }
    }
    final chat = _chats.where((c) => c.topic == topic).firstOrNull;
    if (chat == null) return null;
    final key = await _keyFor(chat);
    if (key == null) return null;
    final clear = await MessageCrypto.decryptEnvelope(payload, key);
    if (clear == null) return null;
    final data = decodeBody(clear);
    if (data == null) return null;

    final me = await _fingerprint();
    final from = data['from'] as String? ?? data['f'] as String? ?? '';
    // Our own traffic comes back from the broker on the same topic.
    if (from.isNotEmpty && from == me) return null;

    if (isCallEnvelope(data)) {
      final kind = data['call'] as String?;
      if (kind == 'offer') {
        return BackgroundRead(
          kind: BackgroundReadKind.incomingCall,
          chatId: chat.id,
          chatTitle: chat.title,
          from: from,
        );
      }
      if (kind == 'end' || kind == 'decline') {
        return BackgroundRead(
          kind: BackgroundReadKind.callEnded,
          chatId: chat.id,
          chatTitle: chat.title,
          from: from,
        );
      }
      // Answers, ICE and relayed audio are the app's business, not ours.
      return null;
    }
    if (isPlumbingEnvelope(data)) return null;

    final message = RevampMessage.fromJson(data);
    if (message == null) return null;
    return BackgroundRead(
      kind: BackgroundReadKind.message,
      chatId: chat.id,
      chatTitle: chat.title,
      from: from,
      senderName: chat.isDm ? '' : message.name,
      preview: message.hasImage && message.text.isEmpty
          ? 'Photo'
          : message.text,
    );
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
    if (data['type'] == 'call') {
      // Ring/answer/ICE traffic rides inside the pair's encrypted channel,
      // so calls need no server of their own. Our own signalling comes back
      // from the broker on the same topic: ignore it, or the caller rings
      // itself, finds itself busy, and declines its own call.
      if (data['from'] == await _fingerprint()) return;
      await onCallSignal?.call(chat, data);
      return;
    }
    if (data['type'] == 'receipt') {
      await _applyReceipt(chat, data);
      return;
    }
    if (data['type'] == 'group_rename' ||
        data['type'] == 'group_delete' ||
        data['type'] == 'group_admins') {
      await _applyGroupControl(chat, data);
      return;
    }
    final message = RevampMessage.fromJson(data);
    if (message == null) return;
    final myFp = await _fingerprint();
    if (message.from == myFp && message.from.isNotEmpty) {
      // Our own message echoed back (broker loopback or replay).
      await _append(chat, message, countUnread: false);
      return;
    }
    final isNew = await _append(chat, message, countUnread: true);
    // Acknowledged whether or not it is new: a resend usually means the
    // first receipt was the part that went missing.
    _acknowledge(chat, message.ts);
    if (isNew) {
      await NotificationService.instance.showMessage(
        chatId: chat.id,
        chatTitle: chat.title,
        sender: chat.isDm ? '' : message.name,
        preview: message.text,
      );
    }
  }

  /// Applies a rename/delete/admin instruction, but only when it is signed
  /// by the group's creator (or, for rename and delete, by an admin the
  /// creator appointed). Anyone holding the channel key could otherwise
  /// forge one.
  Future<void> _applyGroupControl(
      ChatEntry chat, Map<String, dynamic> data) async {
    if (chat.isDm) return;
    final by = data['by'] as String? ?? '';
    final sig = data['sig'] as String? ?? '';
    final ts = (data['ts'] as num?)?.toInt() ?? 0;
    if (by.isEmpty || sig.isEmpty) return;
    if (chat.creatorKey.isEmpty) {
      // We joined before owners were recorded: trust the first signed
      // instruction we see and pin that key from now on.
      chat.creatorKey = by;
    }
    final fromCreator = chat.creatorKey == by;
    final fromAdmin = chat.admins.contains(by);
    if (!fromCreator && !fromAdmin) return;

    if (data['type'] == 'group_admins') {
      // Only the creator decides who administers the group.
      if (!fromCreator) return;
      final admins = data['admins'] == null
          ? <String>[]
          : List<String>.from(data['admins']);
      final ok = await IdentityService.verifyPayload(
          'group_admins:${chat.slug}:${admins.join(',')}:$ts', sig, by);
      if (!ok) return;
      chat.admins = admins;
      await _saveChats();
      notifyListeners();
      return;
    }

    if (data['type'] == 'group_delete') {
      final ok = await IdentityService.verifyPayload(
          'group_delete:${chat.slug}:$ts', sig, by);
      if (!ok) return;
      await removeChat(chat);
      return;
    }

    final newName = (data['name'] as String? ?? '').trim();
    final newSlug = data['slug'] as String? ?? '';
    if (newName.isEmpty || newSlug.isEmpty) return;
    final ok = await IdentityService.verifyPayload(
        'group_rename:${chat.slug}:$newSlug:$newName:$ts', sig, by);
    if (!ok) return;
    if (newSlug != chat.slug) {
      if (_chats.any((c) => c.id == 'group:$newSlug' && c.id != chat.id)) {
        // Already following the renamed group: drop the stale entry.
        await removeChat(chat);
        return;
      }
      await _moveChatStorage(chat, 'group:$newSlug');
      chat.topic = '$chatTopicPrefix/group/$newSlug';
    }
    chat.title = newName;
    await _saveChats();
    notifyListeners();
  }
}
