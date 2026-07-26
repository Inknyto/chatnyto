import 'dart:math';

import 'package:flutter/material.dart';

import '../crypto/crypto_service.dart';
import '../widgets/liquid_glass.dart';
import 'broker_service.dart';

/// The mesh as a picture: this device in the middle, each network around
/// it, and the people discovered on those networks hanging off them.
///
/// It is the same information as the Networks list, laid out so you can see
/// at a glance what is reachable and through which broker.
class NetworkGraphPage extends StatefulWidget {
  const NetworkGraphPage({super.key});

  @override
  State<NetworkGraphPage> createState() => _NetworkGraphPageState();
}

class _NetworkGraphPageState extends State<NetworkGraphPage>
    with SingleTickerProviderStateMixin {
  final BrokerService _brokers = BrokerService.instance;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  String _me = 'You';

  @override
  void initState() {
    super.initState();
    _brokers.addListener(_onChanged);
    if (IdentityService.instance.isUnlocked) {
      IdentityService.instance.publicIdentity().then((identity) {
        if (mounted) setState(() => _me = identity.name);
      });
    }
  }

  @override
  void dispose() {
    _brokers.removeListener(_onChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brokers = _brokers.brokers;
    final peers = _brokers.peers;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Network map'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                await _brokers.autoConnectAll();
                await _brokers.advertiseEverywhere();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: brokers.isEmpty
                  ? const Center(
                      child: LiquidGlass(
                        margin: EdgeInsets.all(24),
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No networks yet.\nAdd or scan for one to see the '
                          'map.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => CustomPaint(
                        painter: _GraphPainter(
                          brokers: brokers,
                          peers: peers,
                          isConnected: _brokers.isConnected,
                          me: _me,
                          phase: _pulse.value,
                          scheme: Theme.of(context).colorScheme,
                        ),
                        size: Size.infinite,
                      ),
                    ),
            ),
            LiquidGlass(
              margin: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _Legend(color: Colors.greenAccent, label: 'Connected'),
                  _Legend(color: Colors.orangeAccent, label: 'Unreachable'),
                  _Legend(color: Colors.lightBlueAccent, label: 'Person'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.brokers,
    required this.peers,
    required this.isConnected,
    required this.me,
    required this.phase,
    required this.scheme,
  });

  final List<Broker> brokers;
  final List<PublicIdentity> peers;
  final bool Function(Broker) isConnected;
  final String me;
  final double phase;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.30;
    final onSurface = scheme.onSurface;

    // Ring of brokers around this device.
    final positions = <Offset>[];
    for (var i = 0; i < brokers.length; i++) {
      final angle = -pi / 2 + i * 2 * pi / brokers.length;
      positions.add(centre + Offset(cos(angle), sin(angle)) * radius);
    }

    // Spokes: this device to each network.
    for (var i = 0; i < brokers.length; i++) {
      final connected = isConnected(brokers[i]);
      final paint = Paint()
        ..color = (connected ? Colors.greenAccent : Colors.orangeAccent)
            .withOpacity(connected ? 0.75 : 0.35)
        ..strokeWidth = connected ? 2.4 : 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(centre, positions[i], paint);
      if (connected) {
        // A dot travelling along the link makes live traffic legible.
        final t = (phase + i / brokers.length) % 1.0;
        canvas.drawCircle(
          Offset.lerp(centre, positions[i], t)!,
          3,
          Paint()..color = Colors.greenAccent.withOpacity(1 - t),
        );
      }
    }

    // People are attached to the connected networks, spread on an outer arc.
    final connectedIndexes = [
      for (var i = 0; i < brokers.length; i++)
        if (isConnected(brokers[i])) i,
    ];
    if (connectedIndexes.isNotEmpty) {
      final peerRadius = radius * 1.85;
      for (var p = 0; p < peers.length; p++) {
        final anchor = connectedIndexes[p % connectedIndexes.length];
        final spread = (p ~/ connectedIndexes.length) - 0.5;
        final baseAngle =
            -pi / 2 + anchor * 2 * pi / brokers.length + spread * 0.28;
        final position =
            centre + Offset(cos(baseAngle), sin(baseAngle)) * peerRadius;
        canvas.drawLine(
          positions[anchor],
          position,
          Paint()
            ..color = Colors.lightBlueAccent.withOpacity(0.45)
            ..strokeWidth = 1.2,
        );
        _node(canvas, position, 16, Colors.lightBlueAccent,
            peers[p].name.isEmpty ? '?' : peers[p].name[0].toUpperCase(),
            onSurface);
        _label(canvas, position + const Offset(0, 24), peers[p].name,
            onSurface.withOpacity(0.75), 10);
      }
    }

    // Networks.
    for (var i = 0; i < brokers.length; i++) {
      final connected = isConnected(brokers[i]);
      _node(
        canvas,
        positions[i],
        22,
        connected ? Colors.greenAccent : Colors.orangeAccent,
        null,
        onSurface,
        icon: connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
      );
      _label(canvas, positions[i] + const Offset(0, 32), brokers[i].name,
          onSurface, 11);
    }

    // This device, with a slow halo so it reads as the centre.
    canvas.drawCircle(
      centre,
      34 + 6 * sin(phase * 2 * pi),
      Paint()..color = scheme.primary.withOpacity(0.18),
    );
    _node(canvas, centre, 26, scheme.primary, null, onSurface,
        icon: Icons.smartphone_rounded);
    _label(canvas, centre + const Offset(0, 40), me, onSurface, 12);
  }

  void _node(Canvas canvas, Offset centre, double radius, Color color,
      String? initial, Color textColor,
      {IconData? icon}) {
    canvas.drawCircle(centre, radius, Paint()..color = color.withOpacity(0.22));
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (icon != null) {
      final builder = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: radius,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      builder.paint(canvas, centre - Offset(builder.width / 2, builder.height / 2));
    } else if (initial != null) {
      _label(canvas, centre, initial, textColor, radius * 0.9, centred: true);
    }
  }

  void _label(Canvas canvas, Offset at, String text, Color color, double size,
      {bool centred = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    painter.paint(
      canvas,
      at - Offset(painter.width / 2, centred ? painter.height / 2 : 0),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
