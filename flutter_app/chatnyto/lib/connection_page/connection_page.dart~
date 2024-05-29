// connection_page/connection_page.dart
import 'package:flutter/material.dart';

class ConnectionPage extends StatefulWidget {
  final Function(String) updateBrokerIP;

  final String brokerIP;

  const ConnectionPage(
      {super.key, required this.updateBrokerIP, required this.brokerIP});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  late TextEditingController _brokerIPController ;
  
  @override
  void initState() {
    super.initState();
    _brokerIPController = TextEditingController(text: widget.brokerIP);
  }
  
  @override
  void dispose() {
    _brokerIPController.dispose();
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
          ],
        ),
      ),
    );
  }
}
