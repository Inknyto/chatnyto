import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';

/// A named MQTT broker the user has registered. Username/password are
/// optional, for brokers that require authentication.
class Broker {
  Broker({
    required this.name,
    required this.host,
    this.port = 1883,
    this.username = '',
    this.password = '',
    this.autoConnect = true,
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

  Broker copyWith({bool? autoConnect}) => Broker(
        name: name,
        host: host,
        port: port,
        username: username,
        password: password,
        autoConnect: autoConnect ?? this.autoConnect,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        if (username.isNotEmpty) 'user': username,
        if (password.isNotEmpty) 'pass': password,
        'auto': autoConnect,
      };

  static Broker fromJson(Map<String, dynamic> json) => Broker(
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 1883,
        username: json['user'] as String? ?? '',
        password: json['pass'] as String? ?? '',
        autoConnect: json['auto'] as bool? ?? true,
      );
}

/// How a broker's host string turns into an mqtt_client connection.
///
/// Accepted forms:
///   192.168.4.1                → plain MQTT on the broker's port
///   mqtt://host  / mqtts://host → plain / TLS MQTT
///   ws://host/mqtt / wss://host/mqtt → MQTT over WebSockets, which is what
///                                works through an HTTPS reverse proxy or a
///                                Cloudflare-style tunnel
/// A port in the URL wins over the broker's configured port; otherwise the
/// scheme's default applies (1883, 8883, 80, 443).
class _BrokerAddress {
  _BrokerAddress({
    required this.server,
    required this.port,
    required this.secure,
    required this.webSocket,
  });

  final String server;
  final int port;
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
    final defaultPort = isWebSocket ? (isSecure ? 443 : 80) : (isSecure ? 8883 : 1883);
    final port = uri.hasPort
        ? uri.port
        : (broker.port != 1883 ? broker.port : defaultPort);
    if (isWebSocket) {
      // mqtt_client wants the scheme and path for websockets, but the port
      // is passed separately.
      final path = uri.path.isEmpty ? '/mqtt' : uri.path;
      return _BrokerAddress(
        server: '$scheme://${uri.host}$path',
        port: port,
        secure: isSecure,
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
  final Map<String, PublicGroupAd> _publicGroups = {};
  bool _loaded = false;
  Timer? _heartbeat;

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

  List<Broker> get brokers => List.unmodifiable(_brokers);
  List<PublicIdentity> get peers => List.unmodifiable(_peers.values);

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

  Future<void> addBroker(Broker broker) async {
    _brokers.removeWhere((b) => b.name == broker.name);
    _brokers.add(broker);
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
    final clientId =
        'chatnyto-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final address = _BrokerAddress.parse(broker);
    final client =
        MqttServerClient.withPort(address.server, clientId, address.port)
          ..keepAlivePeriod = 30
          ..autoReconnect = true
          ..useWebSocket = address.webSocket
          ..secure = address.secure;
    if (address.webSocket) {
      client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    }
    client.onDisconnected = notifyListeners;
    try {
      await client.connect(
        broker.username.isEmpty ? null : broker.username,
        broker.password.isEmpty ? null : broker.password,
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
            onChatMessage?.call(
                event.topic, utf8.decode(payload.payload.message));
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

    await advertiseIdentity(broker);
    notifyListeners();
    return true;
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
  void publishToAll(String topic, String payload, {bool retain = false}) {
    final builder = MqttClientPayloadBuilder()..addString(payload);
    for (final client in _clients.values) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
            retain: retain);
      }
    }
  }

  bool get anyConnected => _brokers.any(isConnected);

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
  Future<void> autoConnectAll() async {
    await load();
    if (!await autoConnectEnabled()) return;
    for (final broker in List<Broker>.from(_brokers)) {
      if (broker.autoConnect && !isConnected(broker)) {
        await connect(broker);
      }
    }
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
      socket.add(Uint8List.fromList([0x10, ..._remainingLength(body.length), ...body]));
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
