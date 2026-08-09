// ~/Documents/git/chatnyto/flutter_app/chatnyto/lib/core/brokers/broker_service.dart 27 Jul 2026 at 01:36:24 PM
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import 'broker_credentials.dart';

/// A named MQTT broker the user has registered.
///
/// [username] and [password] are carried in memory only — long enough to
/// hand a newly added broker's sign-in to [BrokerCredentials], which keeps
/// it in the platform keystore. They are deliberately absent from [toJson]
/// so no credential is ever written to shared preferences, and the UI reads
/// them back from nowhere.
class Broker {
  Broker({
    required this.name,
    required this.host,
    this.port = 1883,
    this.username = '',
    this.password = '',
    this.autoConnect = true,
    this.lastConnectedAt = 0,
  });

  final String name;
  final String host;
  final int port;
  final String username;
  final String password;

  /// Whether the app reconnects to this broker on its own (at startup, on
  /// every heartbeat and when the network comes back). Toggling a broker
  /// off in the UI clears this, so connection state survives restarts.
  final bool autoConnect;

  /// When this broker last accepted a connection, so the networks list can
  /// put the ones actually in use at the top instead of in the order they
  /// happened to be added.
  final int lastConnectedAt;

  Broker copyWith({bool? autoConnect, int? lastConnectedAt}) => Broker(
        name: name,
        host: host,
        port: port,
        username: username,
        password: password,
        autoConnect: autoConnect ?? this.autoConnect,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'auto': autoConnect,
        'seen': lastConnectedAt,
      };

  /// `user`/`pass` are only still read here to pick up brokers saved by an
  /// older build; [BrokerService.load] moves them into the keystore and
  /// rewrites the entry without them.
  static Broker fromJson(Map<String, dynamic> json) => Broker(
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 1883,
        username: json['user'] as String? ?? '',
        password: json['pass'] as String? ?? '',
        autoConnect: json['auto'] as bool? ?? true,
        lastConnectedAt: (json['seen'] as num?)?.toInt() ?? 0,
      );

  bool get hasLegacyCredentials => username.isNotEmpty || password.isNotEmpty;
}

/// How a broker's host string turns into an mqtt_client connection.
///
/// Accepted forms:
///   192.168.4.1                 → plain MQTT on the broker's port
///   mqtt://host  / mqtts://host → plain / TLS MQTT
///   ws://host/mqtt / wss://host/mqtt → MQTT over WebSockets, which is what
///                                       works through an HTTPS reverse proxy or a
///                                       Cloudflare-style tunnel
/// A port in the URL wins over the broker's configured port; otherwise the
/// scheme's default applies (1883, 8883, 80, 443).
class _BrokerAddress {
  _BrokerAddress({
    required this.server,
    required this.port,
    required this.secure,
    required this.webSocket,
  });

  /// Server hostname or WebSocket URL passed to MqttServerClient.
  final String server;

  final int port;

  /// Used ONLY for raw TCP TLS (mqtts://), NOT for WSS.
  final bool secure;

  final bool webSocket;

  static _BrokerAddress parse(Broker broker) {
    final raw = broker.host.trim();
    final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(raw);
    if (match == null) {
      return _BrokerAddress(
        server: raw,
        port: broker.port,
        secure: false,
        webSocket: false,
      );
    }

    final scheme = match.group(1)!.toLowerCase();
    final uri = Uri.parse(raw);
    final isWebSocket = scheme == 'ws' || scheme == 'wss';
    final isSecure = scheme == 'wss' || scheme == 'mqtts' || scheme == 'ssl';
    final defaultPort =
        isWebSocket ? (isSecure ? 443 : 80) : (isSecure ? 8883 : 1883);

    final port = uri.hasPort
        ? uri.port
        : (broker.port != 1883 ? broker.port : defaultPort);

    if (isWebSocket) {
      // For websockets, MqttServerClient requires the full ws:// or wss:// URL string as the server parameter.
      final path = uri.path.isEmpty ? '/mqtt' : uri.path;
      return _BrokerAddress(
        server: '$scheme://${uri.host}$path',
        port: port,
        secure: false, // WSS handles TLS internally; setting client.secure=true causes raw TCP TLS failure.
        webSocket: true,
      );
    }

    return _BrokerAddress(
      server: uri.host.isEmpty ? raw : uri.host,
      port: port,
      secure: isSecure,
      webSocket: false,
    );
  }
}

/// A message being reassembled from the pieces it was published in.
class _PartialMessage {
  _PartialMessage(this.total) : startedAt = DateTime.now();

  final int total;
  final DateTime startedAt;
  final Map<int, String> pieces = {};

  int get bytes =>
      pieces.values.fold<int>(0, (sum, piece) => sum + piece.length);

  bool get expired =>
      DateTime.now().difference(startedAt) > BrokerService._chunkTimeout;
}

/// An MQTT broker found by scanning the network the device is on.
class DiscoveredBroker {
  DiscoveredBroker({required this.host, required this.port});

  final String host;
  final int port;

  String get label => port == 1883 ? host : '$host:$port';
}

const presenceTopicPrefix = 'chatnyto/presence';
const chatTopicPrefix = 'chatnyto/chat';
const groupsTopicPrefix = 'chatnyto/groups';

/// A public group advertised on the mesh.
class PublicGroupAd {
  PublicGroupAd({
    required this.slug,
    required this.name,
    required this.seenAt,
    this.creatorKey = '',
  });

  final String slug;
  final String name;
  final DateTime seenAt;

  /// Base64 Ed25519 public key of whoever created the group. Members record
  /// it when they join and only accept rename/delete instructions signed
  /// with it.
  final String creatorKey;
}

/// Keeps the user's broker list (add by name / remove), manages one MQTT
/// connection per broker, and advertises the user's public identity on the
/// presence topic of every connected broker.
class BrokerService extends ChangeNotifier {
  BrokerService._();

  static final BrokerService instance = BrokerService._();

  static const _prefKey = 'brokers.v1';
  static const _autoConnectPrefKey = 'networks.autoConnect';

  final List<Broker> _brokers = [];
  final Map<String, MqttServerClient> _clients = {};
  final Map<String, PublicIdentity> _peers = {};

  /// Fingerprint → name of the broker whose presence topic announced them.
  final Map<String, String> _peerNetwork = {};

  /// Fingerprint → when they last announced their presence (for online/offline status).
  final Map<String, DateTime> _peerLastSeen = {};

  final Map<String, PublicGroupAd> _publicGroups = {};
  bool _loaded = false;
  Timer? _heartbeat;

  /// Guards against a second sweep starting while one is still running —
  /// the heartbeat, the lifecycle callback and the UI can all ask at once.
  bool _connecting = false;

  /// When a broker that failed may be tried again, and how long the wait is
  /// up to now. Keyed by broker name.
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, Duration> _backoff = {};

  /// Invoked for every message arriving on `chatnyto/chat/#` of any
  /// connected broker. Set by the chat messenger.
  void Function(String topic, String payload)? onChatMessage;

  /// Invoked on every heartbeat tick so other services (chat sync, group
  /// announcements) can piggyback on the same cadence.
  Future<void> Function()? onHeartbeat;

  List<PublicGroupAd> get publicGroups {
    final list = _publicGroups.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Newest first: what is connected now, then whatever was connected most
  /// recently. A network someone used yesterday is far more likely to be
  /// the one they want than the one they added first and never opened.
  List<Broker> get brokers {
    final sorted = List<Broker>.from(_brokers)
      ..sort((a, b) {
        final live = (isConnected(b) ? 1 : 0) - (isConnected(a) ? 1 : 0);
        if (live != 0) return live;
        return b.lastConnectedAt.compareTo(a.lastConnectedAt);
      });
    return List.unmodifiable(sorted);
  }
  List<PublicIdentity> get peers => List.unmodifiable(_peers.values);

  /// Which network a peer was last heard on, empty when unknown.
  String networkOf(String fingerprint) => _peerNetwork[fingerprint] ?? '';

  /// Whether a peer is online: seen advertising their presence recently (within ~60s).
  /// Unknown peers are considered offline.
  bool isOnline(String fingerprint) {
    final lastSeen = _peerLastSeen[fingerprint];
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen).inSeconds < 60;
  }

  bool isConnected(Broker broker) =>
      _clients[broker.name]?.connectionStatus?.state ==
      MqttConnectionState.connected;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefKey) ?? [];
    _brokers
      ..clear()
      ..addAll(stored
          .map((s) => Broker.fromJson(jsonDecode(s) as Map<String, dynamic>)));

    // Brokers saved by an older build still carry their sign-in in shared
    // preferences. Move it into the keystore once and rewrite the list, so
    // the plain copy stops existing.
    final legacy = _brokers.where((b) => b.hasLegacyCredentials).toList();
    if (legacy.isNotEmpty) {
      for (final broker in legacy) {
        await BrokerCredentials.instance.save(
          broker.name,
          username: broker.username,
          password: broker.password,
        );
      }
      await _save();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKey,
      _brokers.map((b) => jsonEncode(b.toJson())).toList(),
    );
  }

  /// Registers [broker]. Any sign-in it carries is handed straight to the
  /// keystore and never reaches the broker list on disk.
  Future<void> addBroker(Broker broker) async {
    _brokers.removeWhere((b) => b.name == broker.name);
    _brokers.add(broker);
    if (broker.hasLegacyCredentials) {
      await BrokerCredentials.instance.save(
        broker.name,
        username: broker.username,
        password: broker.password,
      );
    }
    await _save();
    notifyListeners();
  }

  /// Remembers whether a broker should be reconnected automatically, so the
  /// set of connected networks survives an app restart.
  Future<void> setAutoConnect(Broker broker, bool enabled) async {
    final index = _brokers.indexWhere((b) => b.name == broker.name);
    if (index == -1) return;
    _brokers[index] = _brokers[index].copyWith(autoConnect: enabled);
    await _save();
    notifyListeners();
  }

  /// Master switch for automatic (re)connection of every network.
  Future<bool> autoConnectEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoConnectPrefKey) ?? true;
  }

  Future<void> setAutoConnectEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoConnectPrefKey, enabled);
    if (enabled) await autoConnectAll();
    notifyListeners();
  }

  Future<void> removeBroker(Broker broker) async {
    await removeBrokerKeepingSignIn(broker);
    await BrokerCredentials.instance.forget(broker.name);
  }

  /// Drops a broker from the list but leaves its stored sign-in alone —
  /// used when editing, which removes and re-adds the entry and must not
  /// make the user type the password again.
  Future<void> removeBrokerKeepingSignIn(Broker broker) async {
    await disconnect(broker);
    _brokers.removeWhere((b) => b.name == broker.name);
    await _save();
    notifyListeners();
  }

  /// Connects to [broker]; advertises identity and collects peer presence.
  ///
  /// The host may be a plain address (`192.168.4.1`), a TLS one
  /// (`mqtts://broker.example.com`), or a WebSocket URL
  /// (`wss://example.com/mqtt`) — which is how a broker behind an HTTPS
  /// reverse proxy or a tunnel is reached.
  Future<bool> connect(Broker broker) async {
    if (isConnected(broker)) return true;
    // The heartbeat, the lifecycle callback and the switch in the UI can all
    // ask for the same broker at once. Without this they each open their own
    // client: the last one wins the slot in [_clients] and the others stay
    // connected but unreachable, delivering every message a second time.
    final inFlight = _inFlight[broker.name];
    if (inFlight != null) return inFlight;
    final attempt = _connectOnce(broker);
    _inFlight[broker.name] = attempt;
    try {
      return await attempt;
    } finally {
      _inFlight.remove(broker.name);
    }
  }

  final Map<String, Future<bool>> _inFlight = {};

  Future<bool> _connectOnce(Broker broker) async {
    final clientId =
        'chatnyto-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final address = _BrokerAddress.parse(broker);

    final client =
        MqttServerClient.withPort(address.server, clientId, address.port)
          ..keepAlivePeriod = 30
          // Long enough for a slow mobile link, short enough that a host
          // which is not there admits it before the user gives up.
          ..connectTimeoutPeriod = 5000
          // Deliberately off. mqtt_client's own reconnection keeps working
          // at a client that never connected in the first place, and a
          // handful of those grinding away in the background is what makes
          // the app stop responding. Retrying is [autoConnectAll]'s job:
          // it knows which networks the user actually wants, and it backs
          // off the ones that are not there.
          ..autoReconnect = false;

    if (address.webSocket) {
      client.useWebSocket = true;
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    } else if (address.secure) {
      client.secure = true;
    }

    // A dropped connection leaves nothing behind: the next sweep makes a
    // fresh client rather than reviving one whose handler has given up.
    client.onDisconnected = () {
      if (identical(_clients[broker.name], client)) {
        _clients.remove(broker.name);
      }
      notifyListeners();
    };
    // The sign-in is fetched from the keystore at the moment of connecting;
    // it is never held on the Broker the UI is showing.
    final sign = await BrokerCredentials.instance.read(broker.name);
    final username = sign.username.isNotEmpty ? sign.username : broker.username;
    final password = sign.password.isNotEmpty ? sign.password : broker.password;
    try {
      await client.connect(
        username.isEmpty ? null : username,
        password.isEmpty ? null : password,
      );
    } catch (_) {
      client.disconnect();
      return false;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      // e.g. bad credentials on an authenticated broker
      client.disconnect();
      return false;
    }
    _clients[broker.name] = client;

    // Attach the listener BEFORE subscribing: retained messages are
    // delivered right after SUBACK and would be lost otherwise (this made
    // every user see only themselves in the People tab).
    client.updates!.listen((events) async {
      for (final event in events) {
        final payload = event.payload;
        if (payload is! MqttPublishMessage) continue;
        if (event.topic.startsWith(chatTopicPrefix)) {
          try {
            final text = utf8.decode(payload.payload.message);
            // A piece of a larger message is put back together here, so
            // nothing above this line ever has to know a message was split.
            final whole = text.startsWith('{"chunk"')
                ? _collectChunk(jsonDecode(text) as Map<String, dynamic>)
                : text;
            if (whole != null) onChatMessage?.call(event.topic, whole);
          } catch (_) {
            // Ignore undecodable chat payloads.
          }
          continue;
        }
        if (event.topic.startsWith(groupsTopicPrefix)) {
          _handleGroupAd(event.topic, payload.payload.message);
          continue;
        }
        if (!event.topic.startsWith(presenceTopicPrefix)) continue;
        try {
          final json = jsonDecode(utf8.decode(payload.payload.message))
              as Map<String, dynamic>;
          final identity = PublicIdentity.fromJson(json);
          if (identity != null && await identity.verify()) {
            _peers[identity.fingerprint] = identity;
            // Remembering which broker carried the announcement is what
            // lets the network map show who is reachable through what.
            _peerNetwork[identity.fingerprint] = broker.name;
            // Track when they were last seen for online/offline status.
            _peerLastSeen[identity.fingerprint] = DateTime.now();
            notifyListeners();
          }
        } catch (_) {
          // Ignore malformed presence payloads.
        }
      }
    });
    client.subscribe('$presenceTopicPrefix/#', MqttQos.atLeastOnce);
    client.subscribe('$chatTopicPrefix/#', MqttQos.atLeastOnce);
    client.subscribe('$groupsTopicPrefix/#', MqttQos.atLeastOnce);

    await _markConnected(broker);
    await advertiseIdentity(broker);
    notifyListeners();
    return true;
  }

  /// Notes that [broker] just worked: it moves to the top of the networks
  /// list, and connecting to it counts as wanting it connected — so a
  /// network only ever goes quiet because its switch was turned off.
  Future<void> _markConnected(Broker broker) async {
    final index = _brokers.indexWhere((b) => b.name == broker.name);
    if (index == -1) return;
    _brokers[index] = _brokers[index].copyWith(
      autoConnect: true,
      lastConnectedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _save();
  }

  /// Tracks the public groups announced on `chatnyto/groups/<slug>`. An
  /// empty payload clears the retained announcement — that's how a creator
  /// withdraws a group after deleting or renaming it.
  void _handleGroupAd(String topic, List<int> raw) {
    final slug = topic.substring(topic.lastIndexOf('/') + 1);
    if (slug.isEmpty) return;
    if (raw.isEmpty) {
      if (_publicGroups.remove(slug) != null) notifyListeners();
      return;
    }
    try {
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final name = json['name'] as String?;
      if (name == null || name.isEmpty) {
        if (_publicGroups.remove(slug) != null) notifyListeners();
        return;
      }
      _publicGroups[json['slug'] as String? ?? slug] = PublicGroupAd(
        slug: json['slug'] as String? ?? slug,
        name: name,
        seenAt: DateTime.now(),
        creatorKey: json['creator'] as String? ?? '',
      );
      notifyListeners();
    } catch (_) {
      // Ignore malformed group announcements.
    }
  }

  /// Removes a retained group announcement from every connected broker.
  void clearGroupAd(String slug) {
    for (final client in _clients.values) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.publishMessage(
          '$groupsTopicPrefix/$slug',
          MqttQos.atLeastOnce,
          MqttClientPayloadBuilder().payload!,
          retain: true,
        );
      }
    }
    _publicGroups.remove(slug);
    notifyListeners();
  }

  Future<void> disconnect(Broker broker) async {
    final client = _clients.remove(broker.name);
    client?.disconnect();
    notifyListeners();
  }

  /// Publishes the user's self-signed public identity (retained) so other
  /// devices on the broker can discover it.
  Future<void> advertiseIdentity(Broker broker) async {
    final client = _clients[broker.name];
    if (client == null ||
        client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    if (!IdentityService.instance.isUnlocked) return;
    final identity = await IdentityService.instance.publicIdentity();
    final builder = MqttClientPayloadBuilder()
      ..addString(jsonEncode(identity.toJson()));
    client.publishMessage(
      '$presenceTopicPrefix/${identity.fingerprint}',
      MqttQos.atLeastOnce,
      builder.payload!,
      retain: true,
    );
  }

  Future<void> advertiseEverywhere() async {
    for (final broker in _brokers) {
      await advertiseIdentity(broker);
    }
  }

  /// Publishes [payload] on [topic] over every connected broker — the
  /// caller never needs to know which broker carries the message. Set
  /// [retain] for announcements that late joiners must still receive.
  ///
  /// Anything larger than a single [_chunkBytes] slice is split up first;
  /// see [_publishInPieces] for why.
  void publishToAll(String topic, String payload, {bool retain = false}) {
    if (payload.length > _chunkBytes && !retain) {
      unawaited(_publishInPieces(topic, payload));
      return;
    }
    _publishOnce(topic, payload, retain: retain);
  }

  void _publishOnce(String topic, String payload, {bool retain = false}) {
    final builder = MqttClientPayloadBuilder()..addString(payload);
    for (final client in _clients.values) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
            retain: retain);
      }
    }
  }

  // -------------------------------------------------------------- chunking

  /// How much of a message goes in one MQTT packet.
  ///
  /// A message is published to every connected broker at once, so it has to
  /// fit the smallest of them. The ESP32 broker on the LoRa box grows its
  /// receive buffer 512 bytes at a time out of a heap of a couple of hundred
  /// kilobytes, and a photo — a hundred kilobytes of base64 inside an
  /// encrypted envelope — simply cannot land there: the allocation fails and
  /// the connection is dropped. That is why images worked on mosquitto and
  /// vanished on the LoRa box.
  ///
  /// Two kilobytes leaves room for the topic and the wrapper while staying
  /// well inside what a small broker can hold for each of its subscribers.
  static const _chunkBytes = 2048;

  /// Long enough for the rest of a picture to arrive over a slow link,
  /// short enough that an abandoned half-message is not kept for ever.
  static const _chunkTimeout = Duration(seconds: 90);

  /// A ceiling on what unfinished messages may hold, so a peer that sends
  /// chunk 1 of 10000 and disappears cannot fill this device's memory.
  static const _chunkBufferLimit = 4 * 1024 * 1024;

  var _chunkCounter = 0;
  final Map<String, _PartialMessage> _partials = {};

  /// Sends [payload] as numbered pieces, with a breath between them: the
  /// small broker this exists for has one buffer per subscriber, and
  /// seventy packets pushed back to back overrun it just as surely as one
  /// large one did.
  Future<void> _publishInPieces(String topic, String payload) async {
    final id = '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '-${(_chunkCounter++ & 0xffff).toRadixString(36)}';
    final total = (payload.length + _chunkBytes - 1) ~/ _chunkBytes;
    for (var index = 0; index < total; index++) {
      final start = index * _chunkBytes;
      final end = start + _chunkBytes;
      _publishOnce(
        topic,
        jsonEncode({
          'chunk': id,
          'i': index,
          'n': total,
          'd': payload.substring(
              start, end > payload.length ? payload.length : end),
        }),
      );
      if (index + 1 < total) {
        await Future<void>.delayed(const Duration(milliseconds: 12));
      }
    }
  }

  /// Collects a piece. Returns the whole message once the last one lands,
  /// and null while there is still something missing.
  @visibleForTesting
  String? collectChunk(Map<String, dynamic> json) => _collectChunk(json);

  /// How the pieces of [payload] look on the wire, in order.
  @visibleForTesting
  static List<Map<String, dynamic>> chunksFor(String payload, String id) {
    final total = (payload.length + _chunkBytes - 1) ~/ _chunkBytes;
    return [
      for (var index = 0; index < total; index++)
        {
          'chunk': id,
          'i': index,
          'n': total,
          'd': payload.substring(
            index * _chunkBytes,
            ((index + 1) * _chunkBytes).clamp(0, payload.length),
          ),
        },
    ];
  }

  String? _collectChunk(Map<String, dynamic> json) {
    final id = json['chunk'] as String?;
    final index = (json['i'] as num?)?.toInt();
    final total = (json['n'] as num?)?.toInt();
    final data = json['d'] as String?;
    if (id == null || index == null || total == null || data == null) {
      return null;
    }
    if (total <= 0 || index < 0 || index >= total) return null;

    _partials.removeWhere((_, partial) => partial.expired);
    var buffered = _partials.values.fold<int>(0, (sum, p) => sum + p.bytes);
    if (buffered > _chunkBufferLimit) {
      // Drop the oldest rather than this one: whatever is filling memory is
      // more likely the abandoned message than the one still arriving.
      final oldest = _partials.entries.toList()
        ..sort((a, b) => a.value.startedAt.compareTo(b.value.startedAt));
      for (final entry in oldest) {
        if (buffered <= _chunkBufferLimit) break;
        buffered -= entry.value.bytes;
        _partials.remove(entry.key);
      }
    }

    final partial = _partials.putIfAbsent(id, () => _PartialMessage(total));
    if (partial.total != total) return null;
    partial.pieces[index] = data;
    if (partial.pieces.length < total) return null;
    _partials.remove(id);
    return [for (var i = 0; i < total; i++) partial.pieces[i]!].join();
  }

  bool get anyConnected => _brokers.any(isConnected);

  /// True when at least one connected broker lives outside this network —
  /// which is to say, the device already has a working route to the
  /// internet. Calls use it to decide whether reaching a public STUN server
  /// is worth trying; offline, the app still makes no outside connection.
  bool get hasInternetNetwork =>
      _brokers.where(isConnected).any((b) => !_isLocalAddress(b.host));

  /// Recognises the addresses that can only mean "somewhere on this
  /// network": loopback, the private IPv4 ranges, link-local, and the
  /// hostnames a LAN hands out.
  static bool _isLocalAddress(String host) {
    var name = host.trim().toLowerCase();
    final scheme = name.indexOf('://');
    if (scheme != -1) name = name.substring(scheme + 3);
    name = name.split('/').first.split(':').first;
    if (name.isEmpty || name == 'localhost') return true;
    if (name.endsWith('.local') || !name.contains('.')) return true;
    final parts = name.split('.');
    if (parts.length != 4 || parts.any((p) => int.tryParse(p) == null)) {
      return false;
    }
    final octets = parts.map(int.parse).toList();
    if (octets[0] == 127 || octets[0] == 10) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    if (octets[0] == 169 && octets[1] == 254) return true;
    return false;
  }

  /// First-run defaults so non-technical users never configure brokers:
  /// the Heltec LoRa broker's access-point address and this device.
  Future<void> ensureDefaults() async {
    await load();
    if (_brokers.isNotEmpty) return;
    await addBroker(Broker(name: 'Local LoRa network', host: '192.168.4.1'));
    await addBroker(Broker(name: 'This device', host: '127.0.0.1'));
  }

  /// Tries to connect every registered broker the user hasn't switched off;
  /// failures are silent so the app keeps working with whichever network is
  /// reachable.
  /// A few at a time, and never the ones that just failed.
  ///
  /// One after another is too slow: a broker that is not there takes the
  /// full connect timeout to say so, and a list of them is half a minute
  /// during which the network that *is* reachable stays unconnected and the
  /// app looks broken on startup.
  ///
  /// All at once is worse. Every unreachable host means a DNS lookup and a
  /// socket that sits there until it times out, and a device that has
  /// collected a dozen networks over the months will stall its own interface
  /// trying them simultaneously — which is an app that freezes on launch.
  /// Three at a time, with a pause between batches, keeps both problems
  /// small.
  static const _connectBatch = 3;

  Future<void> autoConnectAll() async {
    if (_connecting) return;
    await load();
    if (!await autoConnectEnabled()) return;
    final now = DateTime.now();
    final wanted = _brokers
        .where((b) =>
            b.autoConnect &&
            !isConnected(b) &&
            !(_retryAfter[b.name]?.isAfter(now) ?? false))
        .toList(growable: false);
    if (wanted.isEmpty) return;

    _connecting = true;
    try {
      for (var start = 0; start < wanted.length; start += _connectBatch) {
        final batch = wanted.skip(start).take(_connectBatch);
        await Future.wait(batch.map((broker) async {
          try {
            if (await connect(broker)) {
              _retryAfter.remove(broker.name);
              _backoff.remove(broker.name);
            } else {
              _noteFailure(broker);
            }
          } catch (error) {
            debugPrint('Could not connect ${broker.name}: $error');
            _noteFailure(broker);
          }
        }));
        // Somewhere for the rest of the app to get a word in.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      _connecting = false;
    }
  }

  /// Backs a failed broker off, so a network that is simply not here stops
  /// being retried every thirty seconds for the rest of the day.
  void _noteFailure(Broker broker) {
    final previous = _backoff[broker.name] ?? Duration.zero;
    final next = previous == Duration.zero
        ? const Duration(seconds: 60)
        : (previous * 2);
    final capped = next > const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : next;
    _backoff[broker.name] = capped;
    _retryAfter[broker.name] = DateTime.now().add(capped);
  }

  /// Clears the backoff for every network — used when something changed
  /// that makes a retry worth it now, like coming back to the foreground.
  void retryNow() {
    _retryAfter.clear();
    _backoff.clear();
  }

  // ------------------------------------------------------------- discovery

  /// Scans the networks this device is on for reachable MQTT brokers, so a
  /// user can join a broker somebody else is running without being told its
  /// address. Every candidate is verified with a real MQTT handshake, not
  /// just an open port.
  Future<List<DiscoveredBroker>> discoverLocalBrokers({
    int port = 1883,
    void Function(double progress)? onProgress,
  }) async {
    final subnets = <String>{};
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          final parts = address.address.split('.');
          if (parts.length == 4) {
            subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }
    } catch (_) {
      // No network interfaces available; fall through to the defaults.
    }
    // The Heltec broker's own access point, even when we're not on it yet.
    subnets.add('192.168.4');

    final found = <DiscoveredBroker>[];
    final hosts = [
      for (final subnet in subnets)
        for (var i = 1; i <= 254; i++) '$subnet.$i',
    ];
    const batchSize = 48;
    for (var start = 0; start < hosts.length; start += batchSize) {
      final batch = hosts.skip(start).take(batchSize);
      final results = await Future.wait(
        batch.map((host) async => await _probeMqtt(host, port) ? host : null),
      );
      for (final host in results.whereType<String>()) {
        found.add(DiscoveredBroker(host: host, port: port));
      }
      onProgress?.call((start + batchSize) / hosts.length);
    }
    return found;
  }

  /// Opens a TCP connection and performs an MQTT CONNECT/CONNACK exchange.
  /// A broker that refuses the connection (bad credentials, for instance)
  /// still answers with a CONNACK, so it counts as found.
  static Future<bool> _probeMqtt(String host, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(milliseconds: 500));
      const clientId = 'chatnyto-scan';
      final idBytes = utf8.encode(clientId);
      final variableHeader = <int>[
        0x00, 0x04, 0x4D, 0x51, 0x54, 0x54, // "MQTT"
        0x04, // protocol level 3.1.1
        0x02, // clean session
        0x00, 0x0A, // keep alive 10s
      ];
      final payload = <int>[
        (idBytes.length >> 8) & 0xFF,
        idBytes.length & 0xFF,
        ...idBytes,
      ];
      final body = [...variableHeader, ...payload];
      socket.add(Uint8List.fromList(
          [0x10, ..._remainingLength(body.length), ...body]));
      await socket.flush();
      final response = await socket
          .timeout(const Duration(milliseconds: 700))
          .first
          .catchError((_) => Uint8List(0));
      // CONNACK has packet type 2 in the high nibble of the first byte.
      return response.isNotEmpty && (response[0] & 0xF0) == 0x20;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static List<int> _remainingLength(int length) {
    final bytes = <int>[];
    var remaining = length;
    do {
      var byte = remaining % 128;
      remaining ~/= 128;
      if (remaining > 0) byte |= 0x80;
      bytes.add(byte);
    } while (remaining > 0);
    return bytes;
  }

  /// Periodic heartbeat: re-advertises presence (brokers without retained-
  /// message support otherwise show late joiners an empty People tab),
  /// retries broker connections, and lets other services piggyback.
  void startHeartbeat({Duration every = const Duration(seconds: 30)}) {
    _heartbeat ??= Timer.periodic(every, (_) async {
      await autoConnectAll();
      await advertiseEverywhere();
      await onHeartbeat?.call();
    });
  }

  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }
}
