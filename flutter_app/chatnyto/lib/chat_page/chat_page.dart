// chat_page/chat_page.dart

import 'dart:io';
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
  bool _isConnected = false; // Add a flag to track the connection status

  @override
  void initState() {
    super.initState();
    _connectToMqttBroker(widget.brokerIP);
  }

  void _connectToMqttBroker(String brokerIP) async {
    String deviceIp = await _getDeviceIPAddress();
    print('device ip to be set ad client id: $deviceIp');
    _mqttClient = MqttServerClient(brokerIP, deviceIp);
    _mqttClient?.onConnected = () {
      if (kDebugMode) {
        print('Connected to MQTT broker: ${widget.brokerIP}');
      }
      _mqttClient?.subscribe('chat', MqttQos.atMostOnce);
      setState(() {
        _isConnected = true; // Update the connection status
      });
    };
    _mqttClient?.onDisconnected = () {
      if (kDebugMode) {
        print('Disconnected from MQTT broker: ${widget.brokerIP}');
      }
      setState(() {
        _isConnected = false; // Update the connection status
      });
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

  Future<String> _getDeviceIPAddress() async {
    String ipAddress = '';
    List<NetworkInterface> interfaces = await printIps();
    for (var interface in interfaces) {
      print('== Interface: ${interface.name} ==');
      for (var addr in interface.addresses) {
        print(
            'one line: ${addr.address} ${addr.host} ${addr.isLoopback} ${addr.rawAddress} ${addr.type.name} :one line');
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          ipAddress = addr.address;
          break;
        }
      }
    }
    if (ipAddress.isEmpty) {
      // i can use ipAdress = 'Not Connected';
      ipAddress = '127.0.0.1';
    }
    print("ip from function return: $ipAddress");
    return ipAddress;
  }

  Future<List<NetworkInterface>> printIps() async {
    List<NetworkInterface> interfaces = [];
    for (var interface in await NetworkInterface.list()) {
      interfaces.add(interface);
    }
    return interfaces;
  }

  void _sendMessage(String message) {
    print("message to be sent: $message");
    print(widget.brokerIP);
    if (_isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _mqttClient?.publishMessage('chat', MqttQos.atMostOnce, builder.payload!);
      _messageController.clear();
    } else {
      if (kDebugMode) {
        print('MQTT client is not connected.');
      }
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Not Connected'),
            content: const Text('You are not connected to the MQTT broker.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatnyto'),
      ),
      body: Column(
        children: [
          Text(
            _isConnected ? '🟢Online' : '🔴Offline',
            style: const TextStyle(color: Colors.black),
          ), // Show the connection status
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
