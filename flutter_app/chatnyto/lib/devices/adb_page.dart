import 'package:flutter/material.dart';

import 'adb/adb_bridge.dart';
import 'adb/adb_client.dart';
import 'adb/adb_key.dart';
import 'adb/adb_targets.dart';

/// The debugging bridge: everything this phone can drive over adb.
///
/// Three routes, and the screen is arranged as three because they really are
/// different things with different requirements:
///
///  * **Over the network**, spoken by the app itself. Televisions, other
///    phones with wireless debugging on, emulators. Nothing to install.
///  * **Through a computer's adb server**, which lends this phone every
///    device that computer can see, including ones on its USB ports.
///  * **On this phone**, through Shizuku or Termux. Shizuku runs commands
///    with adb's own authority; Termux lends a real adb binary, which is the
///    only way to reach hardware plugged into this phone.
class AdbPage extends StatefulWidget {
  const AdbPage({super.key});

  @override
  State<AdbPage> createState() => _AdbPageState();
}

class _AdbPageState extends State<AdbPage> {
  final AdbTargets _targets = AdbTargets.instance;
  ShizukuState _shizuku = ShizukuState.unsupported;
  bool _termux = false;

  @override
  void initState() {
    super.initState();
    _targets.load();
    _targets.addListener(_onChanged);
    _probeBridges();
  }

  @override
  void dispose() {
    _targets.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _probeBridges() async {
    final shizuku = await AdbBridge.instance.shizukuState();
    final termux = await AdbBridge.instance.termuxAvailable();
    if (!mounted) return;
    setState(() {
      _shizuku = shizuku;
      _termux = termux;
    });
  }

  // ------------------------------------------------------------ targets

  Future<void> _edit({AdbTarget? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final hostController = TextEditingController(text: existing?.host ?? '');
    var kind = existing?.kind ?? AdbTargetKind.device;
    final portController = TextEditingController(
        text: (existing?.port ?? AdbTarget.defaultPort(kind)).toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(existing == null ? 'Add a connection' : 'Edit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<AdbTargetKind>(
                  segments: const [
                    ButtonSegment(
                      value: AdbTargetKind.device,
                      icon: Icon(Icons.tv_rounded),
                      label: Text('Device'),
                    ),
                    ButtonSegment(
                      value: AdbTargetKind.computer,
                      icon: Icon(Icons.computer_rounded),
                      label: Text('Computer'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (chosen) => setInner(() {
                    kind = chosen.first;
                    // The two live on different ports and the user should
                    // not have to know which.
                    portController.text =
                        AdbTarget.defaultPort(kind).toString();
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Living room TV',
                  ),
                ),
                TextField(
                  controller: hostController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: '192.168.1.42',
                  ),
                ),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Port'),
                ),
                const SizedBox(height: 10),
                Text(
                  kind == AdbTargetKind.device
                      ? 'The device needs network debugging turned on. The '
                          'first connection puts a dialog on its screen '
                          'asking whether to allow this phone.'
                      : 'The computer has to be running its adb server where '
                          'this phone can reach it — `adb -a nodaemon '
                          'server`, or the port forwarded over ssh. adb '
                          'listens only to itself otherwise.',
                  style: const TextStyle(fontSize: 12),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final host = hostController.text.trim();
    if (host.isEmpty) return;
    await _targets.save(AdbTarget(
      id: existing?.id ?? AdbTargets.newId(),
      name: nameController.text.trim().isEmpty
          ? host
          : nameController.text.trim(),
      host: host,
      port: int.tryParse(portController.text.trim()) ??
          AdbTarget.defaultPort(kind),
      kind: kind,
    ));
  }

  Future<void> _connect(AdbTarget target) async {
    _say('Connecting to ${target.name}…');
    final message = await _targets.connect(target);
    if (mounted) _say(message);
  }

  Future<void> _open(AdbTarget target) async {
    if (target.kind == AdbTargetKind.computer) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => _ComputerPage(target: target)),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => _ShellPage(target: target)),
    );
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targets = _targets.targets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debugging bridge'),
        actions: [
          IconButton(
            tooltip: 'About the key',
            icon: const Icon(Icons.key_rounded),
            onPressed: _showKeyInfo,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const _Heading('Over the network'),
          if (targets.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Nothing added yet. A television with network debugging on, '
                'another phone with wireless debugging on, or a computer '
                'running its adb server.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          for (final target in targets)
            ListTile(
              leading: Icon(
                target.kind == AdbTargetKind.computer
                    ? Icons.computer_rounded
                    : Icons.tv_rounded,
                color: _targets.isConnected(target.id) ? scheme.primary : null,
              ),
              title: Text(target.name),
              subtitle: Text(
                _targets.statusOf(target.id).isEmpty
                    ? target.address
                    : '${target.address} · ${_targets.statusOf(target.id)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _open(target),
              onLongPress: () => _targetOptions(target),
              trailing: IconButton(
                tooltip: 'Connect',
                icon: const Icon(Icons.link_rounded),
                onPressed: () => _connect(target),
              ),
            ),
          const _Heading('On this phone'),
          ListTile(
            leading: Icon(
              Icons.admin_panel_settings_rounded,
              color: _shizuku == ShizukuState.granted ? scheme.primary : null,
            ),
            title: Text('Shizuku — ${_shizuku.label}'),
            subtitle: Text(_shizuku.hint),
            isThreeLine: true,
            onTap: _shizuku == ShizukuState.granted
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const _ShellPage(target: null)),
                    )
                : () async {
                    if (_shizuku == ShizukuState.denied) {
                      await AdbBridge.instance.requestShizuku();
                    }
                    await _probeBridges();
                  },
          ),
          ListTile(
            leading: Icon(
              Icons.terminal_rounded,
              color: _termux ? scheme.primary : null,
            ),
            title: Text(_termux ? 'Termux — installed' : 'Termux — not found'),
            subtitle: Text(
              _termux
                  ? 'Lends its adb binary, which can reach a device plugged '
                      'into this phone. Needs allow-external-apps=true in '
                      'its properties.'
                  : 'Install Termux and `pkg install android-tools` to drive '
                      'a device over USB from this phone.',
            ),
            isThreeLine: true,
            onTap: _termux
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const _TermuxPage()),
                    )
                : null,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _edit,
        tooltip: 'Add a connection',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Future<void> _targetOptions(AdbTarget target) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheet);
                _edit(existing: target);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Disconnect'),
              onTap: () {
                Navigator.pop(sheet);
                _targets.disconnect(target);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove'),
              onTap: () {
                Navigator.pop(sheet);
                _targets.remove(target);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This phone\'s adb key'),
        content: const Text(
          'Every device you connect to remembers the key this app generated '
          'the first time, which is what "always allow" is remembering. '
          'Forgetting it here means every television, phone and box will ask '
          'again the next time you connect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AdbKey.forget();
              if (mounted) _say('Forgotten. Devices will ask again.');
            },
            child: const Text('Forget it'),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
}

/// A shell against one device — or, when [target] is null, against this
/// phone through Shizuku.
class _ShellPage extends StatefulWidget {
  const _ShellPage({required this.target});

  final AdbTarget? target;

  @override
  State<_ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<_ShellPage> {
  final TextEditingController _command = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final StringBuffer _log = StringBuffer();
  bool _running = false;

  /// The handful worth a button. Everything else is typed.
  static const _quick = [
    ('Devices', 'getprop ro.product.model'),
    ('Home', 'input keyevent 3'),
    ('Back', 'input keyevent 4'),
    ('Wake', 'input keyevent 224'),
    ('Screenshot path', 'ls -la /sdcard/Pictures | head'),
    ('Battery', 'dumpsys battery | head -20'),
  ];

  @override
  void dispose() {
    _command.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run([String? given]) async {
    final command = (given ?? _command.text).trim();
    if (command.isEmpty || _running) return;
    setState(() {
      _running = true;
      _log.writeln('\$ $command');
    });
    final target = widget.target;
    final output = target == null
        ? await AdbBridge.instance.shizukuRun(command)
        : await AdbTargets.instance.shell(target, command);
    if (!mounted) return;
    setState(() {
      _log.writeln(output.trim().isEmpty ? '(no output)' : output.trim());
      _running = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.target?.name ?? 'This phone (Shizuku)';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final (label, command) in _quick)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ActionChip(
                      label: Text(label),
                      onPressed: _running ? null : () => _run(command),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: _scroll,
                child: SelectableText(
                  _log.isEmpty ? 'Nothing run yet.' : _log.toString(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _command,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        hintText: 'shell command',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _running ? null : () => _run(),
                    icon: _running
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The devices behind one computer's adb server.
class _ComputerPage extends StatefulWidget {
  const _ComputerPage({required this.target});

  final AdbTarget target;

  @override
  State<_ComputerPage> createState() => _ComputerPageState();
}

class _ComputerPageState extends State<_ComputerPage> {
  List<AdbDevice> _devices = [];
  bool _loading = true;
  String _note = '';

  AdbHost get _host =>
      AdbHost(widget.target.host, port: widget.target.port);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final devices = await _host.devices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
      _note = devices.isEmpty
          ? 'Nothing attached, or the adb server is not reachable from here.'
          : '';
    });
  }

  Future<void> _connectOverNetwork() async {
    final controller = TextEditingController();
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Attach a device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'address:port',
            hintText: '192.168.1.50:5555',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Attach'),
          ),
        ],
      ),
    );
    if (target == null || target.isEmpty) return;
    final reply = await _host.connectDevice(target);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(reply.trim())));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.target.name),
          actions: [
            IconButton(
              tooltip: 'Attach over the network',
              icon: const Icon(Icons.add_link_rounded),
              onPressed: _connectOverNetwork,
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _refresh,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  if (_note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_note),
                    ),
                  for (final device in _devices)
                    ListTile(
                      leading: Icon(device.usable
                          ? Icons.smartphone_rounded
                          : Icons.phonelink_erase_rounded),
                      title: Text(device.label),
                      subtitle: Text('${device.serial} · ${device.state}'),
                      onTap: device.usable
                          ? () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => _HostShellPage(
                                    host: _host,
                                    device: device,
                                  ),
                                ),
                              )
                          : null,
                    ),
                ],
              ),
      );
}

/// A shell on a device reached through a computer's adb server.
class _HostShellPage extends StatefulWidget {
  const _HostShellPage({required this.host, required this.device});

  final AdbHost host;
  final AdbDevice device;

  @override
  State<_HostShellPage> createState() => _HostShellPageState();
}

class _HostShellPageState extends State<_HostShellPage> {
  final TextEditingController _command = TextEditingController();
  final StringBuffer _log = StringBuffer();
  bool _running = false;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _command.text.trim();
    if (command.isEmpty || _running) return;
    setState(() {
      _running = true;
      _log.writeln('\$ $command');
    });
    final output = await widget.host.shell(widget.device.serial, command);
    if (!mounted) return;
    setState(() {
      _log.writeln(output.trim().isEmpty ? '(no output)' : output.trim());
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.device.label)),
        body: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.isEmpty ? 'Nothing run yet.' : _log.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _command,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          hintText: 'shell command',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _run(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _running ? null : _run,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

/// Termux's own adb, for devices plugged into this phone.
class _TermuxPage extends StatefulWidget {
  const _TermuxPage();

  @override
  State<_TermuxPage> createState() => _TermuxPageState();
}

class _TermuxPageState extends State<_TermuxPage> {
  final TextEditingController _arguments =
      TextEditingController(text: 'devices -l');
  final StringBuffer _log = StringBuffer();
  bool _running = false;

  @override
  void dispose() {
    _arguments.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final line = _arguments.text.trim();
    if (line.isEmpty || _running) return;
    setState(() {
      _running = true;
      _log.writeln('\$ adb $line');
    });
    final output = await AdbBridge.instance
        .termuxAdb(line.split(RegExp(r'\s+')).where((a) => a.isNotEmpty).toList());
    if (!mounted) return;
    setState(() {
      _log.writeln(output.trim().isEmpty ? '(no output)' : output.trim());
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Termux adb')),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Runs Termux\'s adb binary. A device plugged into this '
                'phone\'s USB socket shows up here and nowhere else — an app '
                'has no way to reach the USB host stack on its own.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _log.isEmpty ? 'Nothing run yet.' : _log.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    const Text('adb ',
                        style: TextStyle(fontFamily: 'monospace')),
                    Expanded(
                      child: TextField(
                        controller: _arguments,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _run(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _running ? null : _run,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
