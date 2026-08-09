import 'dart:io';

import 'package:flutter/material.dart';

import '../core/widgets/liquid_glass.dart';
import 'device.dart';
import 'device_service.dart';
import 'tv_remote.dart';

/// Adding or configuring a device.
///
/// The first thing asked is what kind it is, because everything else depends
/// on it: a television needs an address on this WiFi and nothing else, an
/// MQTT device needs no address at all but a set of controls the user
/// defines. Asking for both and greying half out would be shorter to write
/// and worse to use.
class DeviceEditorPage extends StatefulWidget {
  const DeviceEditorPage({super.key, this.existing});

  final Device? existing;

  @override
  State<DeviceEditorPage> createState() => _DeviceEditorPageState();
}

class _DeviceEditorPageState extends State<DeviceEditorPage> {
  late DeviceKind _kind = widget.existing?.kind ?? DeviceKind.mqtt;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late final _room = TextEditingController(text: widget.existing?.room ?? '');
  late List<DeviceControl> _controls =
      List.of(widget.existing?.controls ?? const []);
  bool _scanning = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _room.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the device a name.')),
      );
      return;
    }
    if (_kind.isTelevision && _address.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A television needs its address on this WiFi.')),
      );
      return;
    }
    Navigator.pop(
      context,
      (widget.existing ??
              Device(
                id: DeviceService.newId(),
                name: name,
                kind: _kind,
              ))
          .copyWith(
        name: name,
        kind: _kind,
        address: _address.text.trim(),
        room: _room.text.trim(),
        controls: _controls,
        // Changing where a television lives invalidates whatever it handed
        // us before, so the token goes with it rather than being offered to
        // a different set.
        token: _kind == widget.existing?.kind &&
                _address.text.trim() == widget.existing?.address
            ? widget.existing?.token
            : '',
      ),
    );
  }

  /// Looks for Rokus on this phone's own subnet.
  ///
  /// Only Rokus: they answer an unauthenticated request with their name.
  /// Sweeping for Samsungs and LGs would put a "allow this device?" prompt
  /// on every television in the building, which is not a search.
  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final prefix = await _subnetPrefix();
      if (prefix == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Not on a WiFi network to search.')));
        }
        return;
      }
      final found = await TvRemote.instance.findRokus(prefix);
      if (!mounted) return;
      if (found.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No Roku answered on this network. Samsung and LG sets are '
              'not searched for — add those by address.'),
        ));
        return;
      }
      final picked = await showModalBottomSheet<({String address, String name})>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => LiquidGlass(
          margin: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final device in found)
                ListTile(
                  leading: const Icon(Icons.tv_rounded),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  onTap: () => Navigator.pop(sheetContext, device),
                ),
            ],
          ),
        ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _kind = DeviceKind.roku;
        _address.text = picked.address;
        if (_name.text.trim().isEmpty) _name.text = picked.name;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// The first three octets of this device's own address, which is the only
  /// range worth sweeping.
  Future<String?> _subnetPrefix() async {
    try {
      for (final interface in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length == 4) return parts.take(3).join('.');
        }
      }
    } catch (_) {
      // No interfaces to enumerate: treated as not being on a network.
    }
    return null;
  }

  Future<void> _addControl([DeviceControl? existing]) async {
    final control = await showModalBottomSheet<DeviceControl>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ControlSheet(existing: existing),
    );
    if (control == null) return;
    setState(() {
      if (existing == null) {
        _controls = [..._controls, control];
      } else {
        _controls = [
          for (final c in _controls) if (identical(c, existing)) control else c,
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_isNew ? 'Add device' : 'Configure ${widget.existing!.name}'),
          backgroundColor: Colors.transparent,
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text('What kind of device?',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in DeviceKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
              child: Text(_kind.hint,
                  style: const TextStyle(fontSize: 12)),
            ),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Living room TV',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _room,
              decoration: const InputDecoration(
                labelText: 'Room (optional)',
                helperText: 'Only used to group the list.',
              ),
            ),
            if (_kind.isTelevision) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _address,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Address on this WiFi',
                  hintText: '192.168.1.42',
                  helperMaxLines: 3,
                  helperText:
                      'The television shows this in its network settings. '
                      'Port ${_kind.defaultPort} is used unless the address '
                      'names another.',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore_rounded),
                label: Text(_scanning
                    ? 'Looking on this network…'
                    : 'Find a Roku on this network'),
              ),
            ],
            if (_kind == DeviceKind.mqtt) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 22, 4, 6),
                child: Text('Controls',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Text(
                  'Each control is one topic. A bare name goes under '
                  'chatnyto/devices/; start with a slash to use a topic your '
                  'hardware already publishes on.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              for (final control in _controls)
                LiquidGlass(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: ListTile(
                    leading: Icon(switch (control.kind) {
                      ControlKind.toggle => Icons.toggle_on_rounded,
                      ControlKind.slider => Icons.tune_rounded,
                      ControlKind.button => Icons.touch_app_rounded,
                      ControlKind.reading => Icons.speed_rounded,
                    }),
                    title: Text(control.name),
                    subtitle: Text(
                        '${control.kind.label} · ${DeviceService.fullTopic(control.topic)}'),
                    onTap: () => _addControl(control),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => setState(() => _controls = [
                            for (final c in _controls)
                              if (!identical(c, control)) c,
                          ]),
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => _addControl(),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a control'),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

/// The sheet for one control.
class _ControlSheet extends StatefulWidget {
  const _ControlSheet({this.existing});

  final DeviceControl? existing;

  @override
  State<_ControlSheet> createState() => _ControlSheetState();
}

class _ControlSheetState extends State<_ControlSheet> {
  late ControlKind _kind = widget.existing?.kind ?? ControlKind.toggle;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _topic = TextEditingController(text: widget.existing?.topic ?? '');
  late final _on =
      TextEditingController(text: widget.existing?.onPayload ?? 'ON');
  late final _off =
      TextEditingController(text: widget.existing?.offPayload ?? 'OFF');
  late final _press =
      TextEditingController(text: widget.existing?.pressPayload ?? 'PRESS');
  late final _min =
      TextEditingController(text: (widget.existing?.min ?? 0).toString());
  late final _max =
      TextEditingController(text: (widget.existing?.max ?? 100).toString());
  late final _unit = TextEditingController(text: widget.existing?.unit ?? '');

  @override
  void dispose() {
    for (final controller in [
      _name, _topic, _on, _off, _press, _min, _max, _unit,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _done() {
    if (_name.text.trim().isEmpty || _topic.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A control needs a name and a topic.')),
      );
      return;
    }
    Navigator.pop(
      context,
      DeviceControl(
        name: _name.text.trim(),
        kind: _kind,
        topic: _topic.text.trim(),
        onPayload: _on.text,
        offPayload: _off.text,
        pressPayload: _press.text,
        min: double.tryParse(_min.text) ?? 0,
        max: double.tryParse(_max.text) ?? 100,
        unit: _unit.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'New control' : 'Edit control',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final kind in ControlKind.values)
                    ChoiceChip(
                      label: Text(kind.label),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'Ceiling light'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _topic,
                decoration: InputDecoration(
                  labelText: 'Topic',
                  hintText: 'kitchen/light',
                  helperMaxLines: 2,
                  helperText: _topic.text.trim().isEmpty
                      ? null
                      : 'Publishes to ${DeviceService.fullTopic(_topic.text)}',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_kind == ControlKind.toggle) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _on,
                        decoration:
                            const InputDecoration(labelText: 'On payload'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _off,
                        decoration:
                            const InputDecoration(labelText: 'Off payload'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_kind == ControlKind.button) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _press,
                  decoration: const InputDecoration(labelText: 'Payload'),
                ),
              ],
              if (_kind == ControlKind.slider) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _min,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Min'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _max,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Max'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_kind == ControlKind.slider ||
                  _kind == ControlKind.reading) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _unit,
                  decoration: const InputDecoration(
                      labelText: 'Unit (optional)', hintText: '°C'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _done, child: const Text('Done')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
