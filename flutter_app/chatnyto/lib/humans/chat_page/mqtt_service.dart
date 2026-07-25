import 'dart:io';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../core/crypto/crypto_service.dart';
import 'models/chat_message.dart';

class MqttService {
  MqttServerClient? _client;
  String? _topicName;
  SecretKey? _channelKey;

  Future<void> connect({
    required String brokerIP,
    required String topicName,
    required String deviceIP,
    required void Function() onConnected,
    required void Function() onDisconnected,
    required void Function(ChatMessage) onMessageReceived,
    String channelSecret = '',
  }) async {
    _client = MqttServerClient(brokerIP, deviceIP);
    _topicName = topicName;
    // All traffic is encrypted; a per-channel passphrase upgrades a public
    // room (key derived from the topic name) to a private channel.
    _channelKey = await MessageCrypto.deriveChannelKey(channelSecret, topicName);

    _client!.onConnected = onConnected;
    _client!.onDisconnected = onDisconnected;

    try {
      await _client!.connect();
      _client!.subscribe(topicName, MqttQos.atMostOnce);

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>> event) async {
        final recMess = event[0].payload as MqttPublishMessage;
        final message = utf8.decode(recMess.payload.message);
        try {
          final decrypted =
              await MessageCrypto.decryptEnvelope(message, _channelKey!);
          // Fall back to plaintext for messages from legacy clients.
          final messageData = jsonDecode(decrypted ?? message);
          final chatMessage = ChatMessage.fromJson(messageData);
          onMessageReceived(chatMessage);
        } catch (_) {
          // Ignore messages we cannot decrypt or parse.
        }
      });
    } catch (e) {
      print('Exception: $e');
      _client!.disconnect();
    }
  }

  Future<void> sendMessage(ChatMessage message) async {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      final messageJson = jsonEncode(message.toJson());
      final envelope =
          await MessageCrypto.encryptEnvelope(messageJson, _channelKey!);
      final builder = MqttClientPayloadBuilder();
      builder.addString(envelope);
      _client!.publishMessage(_topicName!, MqttQos.atMostOnce, builder.payload!);
    }
  }

  void disconnect() {
    _client?.unsubscribe(_topicName!);
    _client?.disconnect();
  }

  Future<String> getDeviceIPAddress() async {
    String ipAddress = '';
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list();
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ipAddress = addr.address;
            break;
          }
        }
        if (ipAddress.isNotEmpty) break;
      }
    } catch (e) {
      print('Error getting IP address: $e');
    }
    return ipAddress.isEmpty ? '127.0.0.1' : ipAddress;
  }
}
