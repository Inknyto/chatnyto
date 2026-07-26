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
  String _query = '';

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

  Future<void> _addBroker() => _brokerDialog();

  /// Add ([existing] == null) or edit a broker, including the optional
  /// username/password for password-protected brokers.
  Future<void> _brokerDialog({Broker? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hostController = TextEditingController(text: existing?.host ?? '');
    final portController =
        TextEditingController(text: (existing?.port ?? 1883).toString());
    final userController =
        TextEditingController(text: existing?.username ?? '');
    final passController =
        TextEditingController(text: existing?.password ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add broker' : 'Edit broker'),
        content: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 8),
              TextField(
                controller: userController,
                decoration: const InputDecoration(
                  labelText: 'Username (optional)',
                  helperText: 'Only for password-protected brokers',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passController,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Password (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
    if (saved == true &&
        nameController.text.isNotEmpty &&
        hostController.text.isNotEmpty) {
      if (existing != null) {
        await _service.disconnect(existing);
        await _service.removeBroker(existing);
      }
      await _service.addBroker(Broker(
        name: nameController.text.trim(),
        host: hostController.text.trim(),
        port: int.tryParse(portController.text) ?? 1883,
        username: userController.text.trim(),
        password: passController.text,
      ));
    }
  }

  /// Long-press edit mode for a broker: edit its parameters or delete it.
  void _showBrokerOptions(Broker broker) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editBroker(broker);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetContext);
                _service.removeBroker(broker);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editBroker(Broker broker) =>
      _brokerDialog(existing: broker);

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

  bool _matches(String text) =>
      _query.isEmpty || text.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final brokers = _service.brokers
        .where((b) => _matches('${b.name} ${b.host}'))
        .toList();
    final peers = _service.peers
        .where((p) => _matches('${p.name} ${p.fingerprint}'))
        .toList();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Networks')),
        floatingActionButton: FloatingActionButton(
          onPressed: _addBroker,
          child: const Icon(Icons.add_rounded),
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              radius: 24,
              child: TextField(
                decoration: const InputDecoration(
                  icon: Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  hintText: 'Search networks and people',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
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
                  onLongPress: () => _showBrokerOptions(broker),
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
