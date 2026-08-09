import 'package:flutter/material.dart';

import '../core/brokers/broker_service.dart';
import '../core/widgets/liquid_glass.dart';
import 'device.dart';
import 'device_editor.dart';
import 'device_service.dart';
import 'tv_remote_page.dart';

/// The IoT section: everything in the house, grouped by room.
///
/// One list for two very different kinds of thing — a relay on your own
/// broker and a television that speaks its manufacturer's protocol — because
/// the user is not thinking about protocols. They are thinking "the lamp"
/// and "the telly", and the difference only shows up in what a tap opens.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final DeviceService _service = DeviceService.instance;

  @override
  void initState() {
    super.initState();
    _service.load();
    _service.addListener(_onChanged);
    BrokerService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    BrokerService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addDevice() async {
    final device = await Navigator.push<Device>(
      context,
      GlassPageRoute(page: const DeviceEditorPage()),
    );
    if (device != null) await _service.add(device);
  }

  Future<void> _edit(Device device) async {
    final edited = await Navigator.push<Device>(
      context,
      GlassPageRoute(page: DeviceEditorPage(existing: device)),
    );
    if (edited != null) await _service.update(edited);
  }

  Future<void> _confirmRemove(Device device) async {
    final gone = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${device.name}?'),
        content: const Text(
            'The device itself is untouched — this only forgets how to reach '
            'it from here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (gone == true) await _service.remove(device);
  }

  void _open(Device device) {
    if (device.kind.isTelevision) {
      Navigator.push(
        context,
        GlassPageRoute(page: TvRemotePage(device: device)),
      );
    } else {
      Navigator.push(
        context,
        GlassPageRoute(page: MqttDevicePage(device: device)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _service.byRoom;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Devices'),
          backgroundColor: Colors.transparent,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addDevice,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add device'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
          children: [
            if (!BrokerService.instance.anyConnected)
              const LiquidGlass(
                margin: EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: Icon(Icons.cloud_off_rounded,
                      color: Colors.orangeAccent),
                  title: Text('No network'),
                  subtitle: Text(
                      'Devices on your broker cannot be reached until a '
                      'network is connected. Televisions on this WiFi still '
                      'work — they do not go through a broker.'),
                ),
              ),
            if (rooms.isEmpty) const _NothingYet(),
            for (final entry in rooms.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                child: Text(
                  entry.key.isEmpty ? 'Everything else' : entry.key,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              for (final device in entry.value)
                _DeviceTile(
                  device: device,
                  onTap: () => _open(device),
                  onEdit: () => _edit(device),
                  onRemove: () => _confirmRemove(device),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    return const LiquidGlass(
      margin: EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.devices_other_rounded, size: 44),
          SizedBox(height: 12),
          Text('Nothing added yet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'Add a television to use this phone as its remote, or anything '
            'on your broker — a relay, a lamp, a sensor — to switch it and '
            'watch what it reports.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final Device device;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  IconData get _icon => switch (device.kind) {
        DeviceKind.mqtt => Icons.memory_rounded,
        _ => Icons.tv_rounded,
      };

  /// What the row says under the name.
  ///
  /// For an MQTT device that is its liveliest fact: what its readings say
  /// right now. A device that has been quiet for a while says so instead of
  /// showing a stale number as though it were current.
  String _subtitle() {
    if (device.kind.isTelevision) {
      return '${device.kind.label} · ${device.address}';
    }
    final service = DeviceService.instance;
    final readings = device.controls
        .where((c) => c.kind == ControlKind.reading)
        .map((c) {
          final value = service.stateOf(DeviceService.fullTopic(c.topic));
          if (value == null) return null;
          final stale = !service.isFresh(DeviceService.fullTopic(c.topic));
          return '${c.name} $value${c.unit}${stale ? ' (old)' : ''}';
        })
        .whereType<String>()
        .toList();
    if (readings.isNotEmpty) return readings.join(' · ');
    final count = device.controls.length;
    return count == 0
        ? 'No controls yet — tap to add one'
        : '$count control${count == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(_icon, size: 30),
        title: Text(device.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_subtitle()),
        onTap: onTap,
        trailing: PopupMenuButton<String>(
          onSelected: (choice) =>
              choice == 'edit' ? onEdit() : onRemove(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Configure')),
            PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

/// One MQTT device: its controls, and what it is reporting.
class MqttDevicePage extends StatefulWidget {
  const MqttDevicePage({super.key, required this.device});

  final Device device;

  @override
  State<MqttDevicePage> createState() => _MqttDevicePageState();
}

class _MqttDevicePageState extends State<MqttDevicePage> {
  final DeviceService _service = DeviceService.instance;

  /// Where a dial has been dragged to but not yet let go of. Publishing on
  /// every pixel of a drag would send a hundred messages for one gesture.
  final Map<String, double> _dragging = {};

  @override
  void initState() {
    super.initState();
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

  Device get _device =>
      _service.devices.firstWhere((d) => d.id == widget.device.id,
          orElse: () => widget.device);

  void _send(DeviceControl control, String payload) {
    if (!_service.send(control, payload)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to a network, so nothing was sent.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = _device;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(device.name),
          backgroundColor: Colors.transparent,
        ),
        body: device.controls.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Text(
                    'This device has no controls yet. Use Configure to add a '
                    'switch, a dial, a button or a reading.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final control in device.controls)
                    _ControlTile(
                      control: control,
                      dragging: _dragging[control.topic],
                      onDrag: (value) =>
                          setState(() => _dragging[control.topic] = value),
                      onSend: (payload) {
                        _dragging.remove(control.topic);
                        _send(control, payload);
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.control,
    required this.dragging,
    required this.onDrag,
    required this.onSend,
  });

  final DeviceControl control;
  final double? dragging;
  final ValueChanged<double> onDrag;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final service = DeviceService.instance;
    final topic = DeviceService.fullTopic(control.topic);
    final value = service.stateOf(topic);
    final fresh = service.isFresh(topic);

    switch (control.kind) {
      case ControlKind.toggle:
        return LiquidGlass(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: SwitchListTile(
            title: Text(control.name),
            // The topic is shown because when a switch does nothing, the
            // topic is the first thing worth checking.
            subtitle: Text(value == null
                ? 'No reply yet · $topic'
                : '$topic${fresh ? '' : ' · last heard a while ago'}'),
            value: value == control.onPayload,
            onChanged: (on) =>
                onSend(on ? control.onPayload : control.offPayload),
          ),
        );

      case ControlKind.slider:
        final current = dragging ??
            double.tryParse(value ?? '') ??
            control.min;
        return LiquidGlass(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(control.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${current.round()}${control.unit}'),
                ],
              ),
              Slider(
                value: current.clamp(control.min, control.max),
                min: control.min,
                max: control.max,
                // Published on release rather than on every pixel: a drag
                // across the slider would otherwise be a hundred messages,
                // which a LoRa link cannot carry and a relay cannot follow.
                onChanged: onDrag,
                onChangeEnd: (v) => onSend(v.round().toString()),
              ),
            ],
          ),
        );

      case ControlKind.button:
        return LiquidGlass(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: const Icon(Icons.touch_app_rounded),
            title: Text(control.name),
            subtitle: Text(topic),
            trailing: FilledButton(
              onPressed: () => onSend(control.pressPayload),
              child: const Text('Send'),
            ),
          ),
        );

      case ControlKind.reading:
        return LiquidGlass(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            leading: Icon(Icons.speed_rounded,
                color: fresh ? Colors.greenAccent : null),
            title: Text(control.name),
            subtitle: Text(value == null
                ? 'Nothing reported yet · $topic'
                : (fresh ? topic : 'Last heard a while ago · $topic')),
            trailing: Text(
              value == null ? '—' : '$value${control.unit}',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        );
    }
  }
}
