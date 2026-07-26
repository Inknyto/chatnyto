import 'package:flutter/material.dart';

import '../widgets/liquid_glass.dart';
import 'broker_qr.dart';
import 'broker_service.dart';
import 'network_graph_page.dart';

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
  bool _scanning = false;
  bool _autoConnect = true;
  List<DiscoveredBroker> _discovered = [];

  @override
  void initState() {
    super.initState();
    _service.load();
    _service.addListener(_onChanged);
    _service.autoConnectEnabled().then((value) {
      if (mounted) setState(() => _autoConnect = value);
    });
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
              leading: const Icon(Icons.qr_code_2_rounded),
              title: const Text('Share by QR code'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  GlassPageRoute(page: BrokerQrPage(broker: broker)),
                );
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
      // Remember the choice: a network switched off stays off across
      // restarts instead of being reconnected by the heartbeat.
      await _service.setAutoConnect(broker, false);
    } else {
      await _service.setAutoConnect(broker, true);
      final ok = await _service.connect(broker);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect to ${broker.name}')),
        );
      }
    }
    if (mounted) setState(() => _busy.remove(broker.name));
  }

  /// Joins a network from somebody else's QR code.
  Future<void> _scanQr() async {
    final broker = await Navigator.push<Broker>(
      context,
      GlassPageRoute(page: const BrokerScanPage()),
    );
    if (broker == null || !mounted) return;
    await _service.addBroker(broker);
    final ok = await _service.connect(broker);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Joined ${broker.name}.'
            : 'Added ${broker.name}, but it is not reachable yet.'),
      ),
    );
  }

  /// Scans the current network for MQTT brokers so the user can join one
  /// without knowing its address.
  Future<void> _scanNetwork() async {
    setState(() {
      _scanning = true;
      _discovered = [];
    });
    final found = await _service.discoverLocalBrokers();
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _discovered = found
          .where((d) => !_service.brokers.any((b) => b.host == d.host))
          .toList();
    });
    if (found.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No brokers found on this network.')),
      );
    }
  }

  Future<void> _addDiscovered(DiscoveredBroker discovered) async {
    await _service.addBroker(Broker(
      name: 'Network at ${discovered.host}',
      host: discovered.host,
      port: discovered.port,
    ));
    setState(() => _discovered.remove(discovered));
    await _service.connect(_service.brokers.last);
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
        appBar: AppBar(
          title: const Text('Networks'),
          actions: [
            IconButton(
              tooltip: 'Scan a network code',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _scanQr,
            ),
            IconButton(
              tooltip: 'Network map',
              icon: const Icon(Icons.hub_rounded),
              onPressed: () => Navigator.push(
                context,
                GlassPageRoute(page: const NetworkGraphPage()),
              ),
            ),
          ],
        ),
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
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.autorenew_rounded),
                    title: const Text('Connect automatically'),
                    subtitle: const Text(
                        'Reconnect the networks you use as soon as they are '
                        'reachable, and stay connected in the background.'),
                    value: _autoConnect,
                    onChanged: (value) async {
                      setState(() => _autoConnect = value);
                      await _service.setAutoConnectEnabled(value);
                    },
                  ),
                  ListTile(
                    leading: _scanning
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore_rounded),
                    title: Text(_scanning
                        ? 'Scanning this network…'
                        : 'Find brokers on this network'),
                    subtitle: const Text(
                        'Looks for public MQTT brokers around you, including '
                        'the LoRa box.'),
                    onTap: _scanning ? null : _scanNetwork,
                  ),
                ],
              ),
            ),
            if (_discovered.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text('Found on this network',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final discovered in _discovered)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.lan_rounded),
                    title: Text(discovered.label),
                    subtitle: const Text('MQTT broker · tap to join'),
                    trailing: const Icon(Icons.add_circle_outline_rounded),
                    onTap: () => _addDiscovered(discovered),
                  ),
                ),
            ],
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
