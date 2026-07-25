import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';

/// A named MQTT broker the user has registered.
class Broker {
  Broker({required this.name, required this.host, this.port = 1883});

  final String name;
  final String host;
  final int port;

  Map<String, dynamic> toJson() => {'name': name, 'host': host, 'port': port};

  static Broker fromJson(Map<String, dynamic> json) => Broker(
        name: json['name'] as String,
        host: json['host'] as String,
        port: (json['port'] as num?)?.toInt() ?? 1883,
      );
}

const presenceTopicPrefix = 'chatnyto/presence';
const chatTopicPrefix = 'chatnyto/chat';

/// Keeps the user's broker list (add by name / remove), manages one MQTT
/// connection per broker, and advertises the user's public identity on the
/// presence topic of every connected broker.
class BrokerService extends ChangeNotifier {
  BrokerService._();

  static final BrokerService instance = BrokerService._();

  static const _prefKey = 'brokers.v1';

  final List<Broker> _brokers = [];
  final Map<String, MqttServerClient> _clients = {};
  final Map<String, PublicIdentity> _peers = {};
  bool _loaded = false;

  /// Invoked for every message arriving on `chatnyto/chat/#` of any
  /// connected broker. Set by the chat messenger.
  void Function(String topic, String payload)? onChatMessage;

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

  Future<void> removeBroker(Broker broker) async {
    await disconnect(broker);
    _brokers.removeWhere((b) => b.name == broker.name);
    await _save();
    notifyListeners();
  }

  /// Connects to [broker]; advertises identity and collects peer presence.
  Future<bool> connect(Broker broker) async {
    if (isConnected(broker)) return true;
    final clientId =
        'chatnyto-${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final client = MqttServerClient.withPort(broker.host, clientId, broker.port)
      ..keepAlivePeriod = 30
      ..autoReconnect = true;
    client.onDisconnected = notifyListeners;
    try {
      await client.connect();
    } catch (_) {
      client.disconnect();
      return false;
    }
    _clients[broker.name] = client;

    client.subscribe('$presenceTopicPrefix/#', MqttQos.atLeastOnce);
    client.subscribe('$chatTopicPrefix/#', MqttQos.atLeastOnce);
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

    await advertiseIdentity(broker);
    notifyListeners();
    return true;
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
  /// caller never needs to know which broker carries the message.
  void publishToAll(String topic, String payload) {
    final builder = MqttClientPayloadBuilder()..addString(payload);
    for (final client in _clients.values) {
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
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

  /// Tries to connect every registered broker; failures are silent so the
  /// app keeps working with whichever network is reachable.
  Future<void> autoConnectAll() async {
    await load();
    for (final broker in List<Broker>.from(_brokers)) {
      if (!isConnected(broker)) {
        await connect(broker);
      }
    }
  }
}
