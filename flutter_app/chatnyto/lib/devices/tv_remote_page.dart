import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/widgets/liquid_glass.dart';
import 'device.dart';
import 'device_service.dart';

/// A television remote.
///
/// Laid out the way a remote is held rather than the way a settings screen
/// is read: the D-pad in the middle where a thumb rests, volume and channel
/// down the sides as rockers, power and home at the top. Every press gives
/// a haptic tick, because a remote whose buttons do nothing you can feel is
/// a remote you keep pressing twice.
class TvRemotePage extends StatefulWidget {
  const TvRemotePage({super.key, required this.device});

  final Device device;

  @override
  State<TvRemotePage> createState() => _TvRemotePageState();
}

class _TvRemotePageState extends State<TvRemotePage> {
  final DeviceService _service = DeviceService.instance;
  String? _trouble;
  bool _busy = false;

  Device get _device => _service.devices
      .firstWhere((d) => d.id == widget.device.id, orElse: () => widget.device);

  Future<void> _press(RemoteKey key) async {
    HapticFeedback.selectionClick();
    // Not awaited to the point of blocking the next press: a remote has to
    // take a second press while the first is still in flight, or holding
    // volume down feels broken.
    setState(() => _busy = true);
    final result = await _service.pressKey(_device, key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _trouble = result.failed ? result.message : null;
    });
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Text(
              '${device.kind.label} · ${device.address}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_trouble != null)
                LiquidGlass(
                  margin: const EdgeInsets.all(10),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded,
                        color: Colors.orangeAccent),
                    title: Text(_trouble!,
                        style: const TextStyle(fontSize: 13)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _trouble = null),
                    ),
                  ),
                ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _key(Icons.power_settings_new_rounded, RemoteKey.power,
                              tint: Colors.redAccent),
                          _key(Icons.home_rounded, RemoteKey.home),
                          _key(Icons.info_outline_rounded, RemoteKey.info),
                          _key(Icons.close_rounded, RemoteKey.exit),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _DPad(onPress: _press),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Rocker(
                            label: 'Vol',
                            onUp: () => _press(RemoteKey.volumeUp),
                            onDown: () => _press(RemoteKey.volumeDown),
                          ),
                          Column(
                            children: [
                              _key(Icons.volume_off_rounded, RemoteKey.mute),
                              const SizedBox(height: 10),
                              const Text('Mute',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 18),
                              _key(Icons.arrow_back_rounded, RemoteKey.back),
                              const SizedBox(height: 10),
                              const Text('Back',
                                  style: TextStyle(fontSize: 11)),
                            ],
                          ),
                          _Rocker(
                            label: 'Ch',
                            onUp: () => _press(RemoteKey.channelUp),
                            onDown: () => _press(RemoteKey.channelDown),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _key(Icons.fast_rewind_rounded, RemoteKey.rewind),
                          _key(Icons.play_arrow_rounded, RemoteKey.playPause,
                              size: 64),
                          _key(Icons.fast_forward_rounded, RemoteKey.forward),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (device.kind == DeviceKind.samsungTv ||
                          device.kind == DeviceKind.lgTv)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'The first press asks the television to allow '
                            'this phone. Say yes on the television, once — '
                            'after that it remembers.',
                            style: TextStyle(fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _key(IconData icon, RemoteKey key, {double size = 52, Color? tint}) {
    return Material(
      color: tint?.withValues(alpha: 0.2) ??
          Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _press(key),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.45, color: tint),
        ),
      ),
    );
  }
}

/// The directional pad, as one round piece rather than five buttons — that
/// is what the thumb expects to find.
class _DPad extends StatelessWidget {
  const _DPad({required this.onPress});

  final void Function(RemoteKey) onPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget arrow(IconData icon, RemoteKey key, Alignment at) {
      return Align(
        alignment: at,
        child: IconButton(
          icon: Icon(icon, size: 26),
          onPressed: () => onPress(key),
        ),
      );
    }

    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Stack(
        children: [
          arrow(Icons.keyboard_arrow_up_rounded, RemoteKey.up,
              Alignment.topCenter),
          arrow(Icons.keyboard_arrow_down_rounded, RemoteKey.down,
              Alignment.bottomCenter),
          arrow(Icons.keyboard_arrow_left_rounded, RemoteKey.left,
              Alignment.centerLeft),
          arrow(Icons.keyboard_arrow_right_rounded, RemoteKey.right,
              Alignment.centerRight),
          Center(
            child: Material(
              color: scheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => onPress(RemoteKey.ok),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Center(
                    child: Text('OK',
                        style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        )),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Volume and channel, shaped like the rockers they are on a real remote.
class _Rocker extends StatelessWidget {
  const _Rocker({
    required this.label,
    required this.onUp,
    required this.onDown,
  });

  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 62,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(31),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: onUp,
          ),
          Text(label, style: const TextStyle(fontSize: 11)),
          IconButton(
            icon: const Icon(Icons.remove_rounded),
            onPressed: onDown,
          ),
        ],
      ),
    );
  }
}
