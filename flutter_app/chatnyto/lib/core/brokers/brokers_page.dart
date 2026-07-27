import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../widgets/liquid_glass.dart';
import 'broker_credentials.dart';
import 'broker_qr.dart';
import 'broker_service.dart';
import 'network_directory.dart';
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

  /// Add ([existing] == null) or edit a broker.
  ///
  /// The address is the only thing normally typed: a server that publishes a
  /// profile answers with its own name, port and sign-in, so `supa-tech.com`
  /// is enough. The sign-in fields are folded away for the brokers that do
  /// need one, and are write-only — an already-saved password is reported as
  /// saved and never rendered back into a field.
  Future<void> _brokerDialog({Broker? existing}) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hostController = TextEditingController(text: existing?.host ?? '');
    final portController = TextEditingController(
        text: existing == null || existing.port == 1883
            ? ''
            : existing.port.toString());
    final userController = TextEditingController();
    final passController = TextEditingController();

    final hasSignIn = existing == null
        ? false
        : await BrokerCredentials.instance.has(existing.name);
    if (!mounted) return;

    var showSignIn = false;
    var clearSignIn = false;
    var checking = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? l10n.addBroker : l10n.editBroker),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: hostController,
                  autofocus: existing == null,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.brokerHost,
                    hintText: 'supa-tech.com',
                    helperMaxLines: 3,
                    helperText: l10n.brokerHostHelp,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.brokerName,
                    helperText: l10n.brokerNameHelp,
                  ),
                ),
                const SizedBox(height: 8),
                if (hasSignIn && !showSignIn)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key_rounded, size: 20),
                    title: Text(
                      clearSignIn ? l10n.signInWillBeRemoved : l10n.signInSaved,
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: TextButton(
                      onPressed: () => setDialogState(() {
                        if (clearSignIn) {
                          clearSignIn = false;
                        } else {
                          showSignIn = true;
                        }
                      }),
                      child: Text(clearSignIn ? l10n.undo : l10n.replace),
                    ),
                  ),
                if (!hasSignIn && !showSignIn)
                  TextButton.icon(
                    onPressed: () => setDialogState(() => showSignIn = true),
                    icon: const Icon(Icons.lock_outline_rounded, size: 18),
                    label: Text(l10n.needsSignIn),
                  ),
                if (showSignIn) ...[
                  TextField(
                    controller: userController,
                    decoration: InputDecoration(
                      labelText: l10n.brokerUsername,
                      helperText: l10n.brokerUsernameHelp,
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passController,
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: l10n.brokerPassword),
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.brokerPortOptional,
                    hintText: '1883',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () {
                      setDialogState(() => checking = true);
                      Navigator.pop(dialogContext, true);
                    },
              child: Text(existing == null ? l10n.add : l10n.save),
            ),
          ],
        ),
      ),
    );

    if (saved != true || hostController.text.trim().isEmpty) return;

    var address = hostController.text.trim();
    var name = nameController.text.trim();
    var port = int.tryParse(portController.text.trim()) ?? 1883;
    var username = userController.text.trim();
    var password = passController.text;

    // Ask the server about itself, so a bare address is enough. Anything the
    // user typed by hand wins over what the profile says.
    if (username.isEmpty && password.isEmpty) {
      final profile = await NetworkDirectory.instance.lookup(address);
      if (profile != null) {
        address = profile.url;
        if (name.isEmpty) name = profile.name;
        if (profile.port != 0) port = profile.port;
        username = profile.username;
        password = profile.password;
      }
    }
    if (name.isEmpty) name = address;

    if (existing != null) {
      await _service.disconnect(existing);
      await BrokerCredentials.instance.rename(existing.name, name);
      await _service.removeBrokerKeepingSignIn(existing);
    }
    await _service.addBroker(Broker(
      name: name,
      host: address,
      port: port,
      username: username,
      password: password,
    ));
    if (clearSignIn && username.isEmpty && password.isEmpty) {
      await BrokerCredentials.instance.forget(name);
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
              title: Text(AppLocalizations.of(context).edit),
              onTap: () {
                Navigator.pop(sheetContext);
                _editBroker(broker);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded),
              title: Text(AppLocalizations.of(context).shareByQr),
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
              title: Text(AppLocalizations.of(context).delete),
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
          SnackBar(
              content: Text(AppLocalizations.of(context)
                  .couldNotConnect(broker.name))),
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
        SnackBar(content: Text(AppLocalizations.of(context).noBrokersFound)),
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
    final l10n = AppLocalizations.of(context);
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
          title: Text(l10n.networks),
          actions: [
            IconButton(
              tooltip: l10n.scanNetworkCode,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _scanQr,
            ),
            IconButton(
              tooltip: l10n.networkMap,
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
                decoration: InputDecoration(
                  icon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  hintText: l10n.searchNetworks,
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
                    title: Text(l10n.connectAutomatically),
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
                    title: Text(_scanning ? l10n.scanning : l10n.findBrokers),
                    subtitle: Text(l10n.findBrokersHelp),
                    onTap: _scanning ? null : _scanNetwork,
                  ),
                ],
              ),
            ),
            if (_discovered.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(l10n.foundOnNetwork,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
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
