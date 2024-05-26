import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  MqttServerClient? _mqttClient;
  final List<String> _messages = [];
  final _messageController = TextEditingController();
  String _currentBrokerIP = '127.0.0.1'; // Default broker IP address
  final _brokerIPController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mqttClient = MqttServerClient(_currentBrokerIP, 'clientId');
    _connectToMqttBroker(_currentBrokerIP);
  }

  void _connectToMqttBroker(String brokerIP) {
    // Listen for the connected event
    _mqttClient?.onConnected = () {
      if (kDebugMode) {
        print('Connected to MQTT broker: $brokerIP');
      }

      // Subscribe to the chat topic
      _mqttClient?.subscribe('chat', MqttQos.atMostOnce);
    };

    // Listen for the disconnected event
    _mqttClient?.onDisconnected = () {
      if (kDebugMode) {
        print('Disconnected from MQTT broker: $brokerIP');
      }
    };

    // Connect to the broker
    _mqttClient?.connect();

    // Listen for incoming messages
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

  void _sendMessage(String message) {
    // Check if the client is connected
    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      // Publish a new message to the chat topic
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _mqttClient?.publishMessage('chat', MqttQos.atMostOnce, builder.payload!);
      _messageController.clear();
    } else {
      // Handle the case when the client is not connected
      if (kDebugMode) {
        print('MQTT client is not connected.');
      }
    }
  }

  void updateBrokerIP(String newBrokerIP) {
    setState(() {
      _currentBrokerIP = newBrokerIP;
    });
    _connectToMqttBroker(newBrokerIP);
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
                  onPressed: () {
                    _sendMessage(_messageController.text);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brokerIPController,
                    decoration: const InputDecoration(
                      hintText: 'Enter new broker IP...',
                    ),
                    onSubmitted: updateBrokerIP,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.update),
                  onPressed: () {
                    updateBrokerIP(_brokerIPController.text);
                  },
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
    _brokerIPController.dispose();
    _messageController.dispose();
    super.dispose();
  }
}
