import 'package:flutter/material.dart';
import '../chat_page/chat_page.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _brokerIPController = TextEditingController(text: '127.0.0.1');
  final _chatPageKey = GlobalKey<ChatPageState>();

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
                print('update button pressed.');
                final newBrokerIP = _brokerIPController.text;
                if (newBrokerIP.isNotEmpty) {
                  print('connection_page 37 newBrokerIp: $newBrokerIP');
                  _chatPageKey.currentState?.updateBrokerIP(newBrokerIP);
                }
              },
              child: const Text('Update Broker IP'),
            ),
          ],
        ),
      ),
    );
  }
}
