import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() => runApp(MQTTChatApp());

class MQTTChatApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MQTT Chat App',
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _messages = <String>[];
  late MqttClient _client;

  @override
  void initState() {
    super.initState();
    _connectToMqttBroker();
  }

  void _connectToMqttBroker() {
    _client = MqttClient('broker.example.com', 'flutter_client');
    _client.subscribe('chat', MqttQos.atMostOnce);
    _client.updates!.listen((event) {
      final message = MqttPublishMessage.fromByteData(event.payload);
      setState(() {
        _messages.add(message.payload.toString());
      });
    });
  }

  void _sendMessage() {
    final message = _controller.text;
    _client.publish('chat', MqttQos.atMostOnce, message.codeUnits);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('MQTT Chat App'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return Text(_messages[index]);
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Enter your message',
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _client.disconnect();
    super.dispose();
  }
}
