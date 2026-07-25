import 'package:flutter/material.dart';

import '../widgets/liquid_glass.dart';
import 'broker_service.dart';

/// Lets the user register brokers by name, connect to and disconnect from
/// each one, and see the peers discovered through presence advertisements.
class BrokersPage extends StatefulWidget {
  const BrokersPage({super.key});

  @override
  State<BrokersPage> createState() => _BrokersPageState();
}

class _BrokersPageState extends State<BrokersPage> {
  final BrokerService _service = BrokerService.instance;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _service.load();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addBroker() async {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '1883');
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add broker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: hostController,
              decoration:
                  const InputDecoration(labelText: 'Host (IP or hostname)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: portController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (added == true &&
        nameController.text.isNotEmpty &&
        hostController.text.isNotEmpty) {
      await _service.addBroker(Broker(
        name: nameController.text.trim(),
        host: hostController.text.trim(),
        port: int.tryParse(portController.text) ?? 1883,
      ));
    }
  }

  Future<void> _toggle(Broker broker) async {
    setState(() => _busy.add(broker.name));
    if (_service.isConnected(broker)) {
      await _service.disconnect(broker);
    } else {
      final ok = await _service.connect(broker);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect to ${broker.name}')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(broker.name));
  }

  @override
  Widget build(BuildContext context) {
    final brokers = _service.brokers;
    final peers = _service.peers;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Brokers')),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBroker,
          child: const Icon(Icons.add_rounded),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (brokers.isEmpty)
              const LiquidGlass(
                margin: EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: Icon(Icons.dns_rounded),
                  title: Text('No brokers yet'),
                  subtitle: Text(
                      'Add a broker by name to start chatting over MQTT/LoRa.'),
                ),
              ),
            for (final broker in brokers)
              LiquidGlass(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: Icon(
                    _service.isConnected(broker)
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    color: _service.isConnected(broker)
                        ? Colors.greenAccent
                        : null,
                  ),
                  title: Text(broker.name),
                  subtitle: Text('${broker.host}:${broker.port}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_busy.contains(broker.name))
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Switch(
                          value: _service.isConnected(broker),
                          onChanged: (_) => _toggle(broker),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _service.removeBroker(broker),
                      ),
                    ],
                  ),
                ),
              ),
            if (peers.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text('Peers on the network',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final peer in peers)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_rounded),
                    title: Text(peer.name),
                    subtitle: Text('key ${peer.fingerprint}'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
