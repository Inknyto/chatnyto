// connection_page/connection_page.dart
import 'package:flutter/material.dart';

class ConnectionPage extends StatefulWidget {
  final Function(String) updateBrokerIP;

  const ConnectionPage({super.key, required this.updateBrokerIP});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _brokerIPController = TextEditingController(text: '127.0.0.1');

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
          ],
        ),
      ),
    );
  }
}
