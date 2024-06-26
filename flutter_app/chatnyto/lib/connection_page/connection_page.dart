// connection_page/connection_page.dart
import 'package:flutter/material.dart';

class ConnectionPage extends StatefulWidget {
  final Function(String) updateBrokerIP;
  final Function(String) updateTopicName;

  final String brokerIP;
  final String topicName;

  const ConnectionPage(
      {super.key,
      required this.updateTopicName,
      required this.topicName,
      required this.updateBrokerIP,
      required this.brokerIP});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late TextEditingController _brokerIPController;
  late TextEditingController _topicNameController;

  @override
  void initState() {
    super.initState();
    _brokerIPController = TextEditingController(text: widget.brokerIP);
    _topicNameController = TextEditingController(text: widget.topicName);
  }

  @override
  void dispose() {
    _brokerIPController.dispose();
    _topicNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Broker IP Address'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _brokerIPController,
              decoration: const InputDecoration(
                labelText: 'Broker IP Address',
              ),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () {
                final newBrokerIP = _brokerIPController.text;
                widget.updateBrokerIP(newBrokerIP);
              },
              child: const Text('Update Broker IP'),
            ),
            TextField(
              controller: _topicNameController,
              decoration: const InputDecoration(
                labelText: 'Topic Name',
              ),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () {
                final newTopicName = _topicNameController.text;
                widget.updateTopicName(newTopicName);
              },
              child: const Text('Update Topic Name'),
            ),
          ],
        ),
      ),
    );
  }
}
