// chat_page/chat_page.dart

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.brokerIP});

  final String brokerIP;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  MqttServerClient? _mqttClient;
  final List<String> _messages = [];
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _connectToMqttBroker(widget.brokerIP);
  }

  void _connectToMqttBroker(String brokerIP) {
    _mqttClient = MqttServerClient(brokerIP, 'clientId');
    _mqttClient?.onConnected = () {
      if (kDebugMode) {
        print('Connected to MQTT broker: ${widget.brokerIP}');
      }
      _mqttClient?.subscribe('chat', MqttQos.atMostOnce);
    };
    _mqttClient?.onDisconnected = () {
      if (kDebugMode) {
        print('Disconnected from MQTT broker: ${widget.brokerIP}');
      }
    };
    _mqttClient?.connect(widget.brokerIP);
    print(widget.brokerIP);
    _mqttClient?.updates
        ?.listen((List<MqttReceivedMessage<MqttMessage?>> event) {
      final recMess = event[0].payload;
      final pubMess = recMess as MqttPublishMessage;
      final topicName = pubMess.variableHeader?.topicName;
      final message = utf8.decode(pubMess.payload.message);
      setState(() {
        _messages.add('Topic Name: $topicName\nMessage: $message');
      });
    });
  }

void updateBrokerIP(String newBrokerIP) {
  _mqttClient?.unsubscribe('chat');
  _mqttClient?.disconnect();
  _mqttClient = null;
  _connectToMqttBroker(newBrokerIP);
}

  void _sendMessage(String message) {
    print("message to be sent: $message");
    print(widget.brokerIP);
    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _mqttClient?.publishMessage('chat', MqttQos.atMostOnce, builder.payload!);
      _messageController.clear();
    } else {
      if (kDebugMode) {
        print('MQTT client is not connected.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT Chat App'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_messages[index]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mqttClient?.unsubscribe('chat');
    _mqttClient?.disconnect();
    _messageController.dispose();
    super.dispose();
  }
}
