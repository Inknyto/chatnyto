// chat_page/chat_page.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key,
      required this.deviceIP,
      required this.brokerIP,
      required this.topicName});

  final String brokerIP;
  final String topicName;
  final String deviceIP;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  MqttServerClient? _mqttClient;
  final List<String> _messages = [];
  final _messageController = TextEditingController();
  bool _isConnected = false; // Add a flag to track the connection status
  String _deviceIp = '';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectToMqttBroker(widget.brokerIP, widget.topicName);
  }

  Future<void> _loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final brokerIP = widget.brokerIP;
    final topicName = widget.topicName;
    // final messagesJson = prefs.getStringList('messages') ?? [];
    final messagesJson = prefs.getStringList('$brokerIP:$topicName') ?? [];
    setState(() {
      _messages.clear();
      _messages.addAll(messagesJson.map((json) => jsonDecode(json)));
    });
  }

  Future<void> _saveMessages() async {
    final brokerIP = widget.brokerIP;
    final topicName = widget.topicName;
    final prefs = await SharedPreferences.getInstance();
    final messagesJson =
        _messages.map((connection) => jsonEncode(connection)).toList();
    print(messagesJson);
    await prefs.setStringList('$brokerIP:$topicName', messagesJson);
  }

  void _connectToMqttBroker(String brokerIP, String topicName) async {
    String deviceIp = await _getDeviceIPAddress();
    if (kDebugMode) {
      print('device ip to be set as client id: $deviceIp');
    }
    _mqttClient = MqttServerClient(brokerIP, deviceIp);
    _mqttClient?.onConnected = () {
      if (kDebugMode) {
        print('Connected to MQTT broker: ${widget.brokerIP}');
      }
      _mqttClient?.subscribe(topicName, MqttQos.atMostOnce);
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
    if (kDebugMode) {
      print(widget.brokerIP);
    }
    _mqttClient?.updates
        ?.listen((List<MqttReceivedMessage<MqttMessage?>> event) {
      final recMess = event[0].payload;

      final pubMess = recMess as MqttPublishMessage;
      print("pubMess: $pubMess");
      final topicName = pubMess.variableHeader?.topicName;

      // final senderIP = utf8.decode(pubMess.payload.message);
      final message = utf8.decode(pubMess.payload.message);

      final sentHour = DateTime.now().hour;
      final sentMinute = DateTime.now().minute;

      setState(() {
        _messages.add('$topicName\n$message\n$sentHour:$sentMinute');
      });
    });
  }

  void updateBrokerIP(String newTopicName, String newBrokerIP) {
    // if it works, do not touch it
    _mqttClient?.unsubscribe(newTopicName);
    _mqttClient?.disconnect();
    _mqttClient = null;
    _connectToMqttBroker(newBrokerIP, newTopicName);
  }

  Future<String> _getDeviceIPAddress() async {
    String ipAddress = '';
    List<NetworkInterface> interfaces = await printIps();
    for (var interface in interfaces) {
      if (kDebugMode) {
        print('== Interface: ${interface.name} ==');
      }
      for (var addr in interface.addresses) {
        if (kDebugMode) {
          print(
              'one line: ${addr.address} ${addr.host} ${addr.isLoopback} ${addr.rawAddress} ${addr.type.name} :one line');
        }
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          ipAddress = addr.address;
          break;
        }
      }
    }
    if (ipAddress.isEmpty) {
      // i can use ipAddress = 'Not Connected';
      ipAddress = '127.0.0.1';
    }
    if (kDebugMode) {
      print("ip from function return: $ipAddress");
    }
    setState(() {
      _deviceIp = ipAddress;
    });

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
    if (kDebugMode) {
      print("message to be sent: $message");
    }
    if (_isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString("$_deviceIp ~> $message");
      _mqttClient?.publishMessage(
          widget.topicName, MqttQos.atMostOnce, builder.payload!);
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
            content: const Text(
              'You are not connected to the MQTT broker.',
              style: TextStyle(color: Colors.black),
            ),
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
        title: Text(
          _isConnected
              ? 'Chatnyto, $_deviceIp		🟢Online'
              : 'Chatnyto, $_deviceIp		🔴Offline',
          style: const TextStyle(color: Colors.black),
        ), // Show the connection status
        //Text('Chatnyto, $_deviceIp'),
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
    _saveMessages();
    _mqttClient?.unsubscribe(widget.topicName);
    _mqttClient?.disconnect();
    _messageController.dispose();
    super.dispose();
  }
}
