import 'dart:math';

import 'package:flutter/material.dart';

import '../../calls/call_page.dart';
import '../../calls/call_service.dart';
import '../../revamp/chat_service.dart';
import '../crypto/crypto_service.dart';
import '../widgets/liquid_glass.dart';
import 'broker_service.dart';

/// What a node on the map stands for.
enum _NodeKind { me, broker, peer }

/// One circle on the map, positioned in graph coordinates — the view's pan
/// and zoom are applied on top, so dragging a node keeps its meaning at any
/// zoom level.
class _Node {
  _Node({
    required this.id,
    required this.label,
    required this.kind,
    required this.at,
    this.broker,
    this.peer,
    this.connected = false,
  });

  final String id;
  final String label;
  final _NodeKind kind;
  Offset at;

  final Broker? broker;
  final PublicIdentity? peer;
  final bool connected;

  double get radius => switch (kind) {
        _NodeKind.me => 26,
        _NodeKind.broker => 22,
        _NodeKind.peer => 16,
      };

  Color get color => switch (kind) {
        _NodeKind.me => Colors.purpleAccent,
        _NodeKind.broker =>
          connected ? Colors.greenAccent : Colors.orangeAccent,
        _NodeKind.peer => Colors.lightBlueAccent,
      };
}

class _Edge {
  _Edge(this.from, this.to, {this.live = false});

  final String from;
  final String to;

  /// A live link gets a travelling dot, so working paths are visible at a
  /// glance rather than inferred from node colours.
  final bool live;
}

/// The mesh as a picture you can handle: this device in the middle, each
/// network around it, and the people discovered on those networks hanging
/// off the network that announced them.
///
/// It is the same information as the Networks list, but a list cannot show
/// a shape. Everything here is direct: drag the background to pan, pinch or
/// use the buttons to zoom, drag a node to arrange the map the way you think
/// about it, and tap a node to see what it is and act on it.
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

  // View transform: screen = graph * scale + pan.
  double _scale = 1;
  Offset _pan = Offset.zero;
  bool _viewPlaced = false;

  /// Positions the user dragged, kept across rebuilds so a live update does
  /// not undo their arrangement.
  final Map<String, Offset> _pinned = {};

  List<_Node> _nodes = [];
  List<_Edge> _edges = [];
  String? _dragging;
  Offset _lastFocal = Offset.zero;
  double _scaleAtGestureStart = 1;

  /// A tap is a gesture that ends about where it started. Deciding this
  /// inside the scale gesture — rather than with a separate tap recogniser —
  /// is what keeps a tap from being swallowed as a one-pixel pan.
  static const _tapSlop = 12.0;
  Offset _gestureStart = Offset.zero;
  bool _movedDuringGesture = false;

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

  // ------------------------------------------------------------- layout

  /// Lays the graph out around the origin: networks on a ring, the people
  /// each network announced on an arc beyond it. A node the user has moved
  /// keeps their position.
  void _rebuildGraph() {
    final brokers = _brokers.brokers;
    final peers = _brokers.peers;
    final nodes = <_Node>[
      _Node(id: '@me', label: _me, kind: _NodeKind.me, at: Offset.zero),
    ];
    final edges = <_Edge>[];

    const ringRadius = 190.0;
    for (var i = 0; i < brokers.length; i++) {
      final broker = brokers[i];
      final angle = -pi / 2 + i * 2 * pi / max(brokers.length, 1);
      final id = 'b:${broker.name}';
      final connected = _brokers.isConnected(broker);
      nodes.add(_Node(
        id: id,
        label: broker.name,
        kind: _NodeKind.broker,
        at: _pinned[id] ??
            Offset(cos(angle), sin(angle)) * ringRadius,
        broker: broker,
        connected: connected,
      ));
      edges.add(_Edge('@me', id, live: connected));
    }

    // Group the people by the network that announced them, so the arc under
    // each network holds exactly its own peers.
    final byNetwork = <String, List<PublicIdentity>>{};
    for (final peer in peers) {
      final network = _brokers.networkOf(peer.fingerprint);
      byNetwork.putIfAbsent(network, () => []).add(peer);
    }

    for (var i = 0; i < brokers.length; i++) {
      final broker = brokers[i];
      final mine = byNetwork[broker.name] ?? const <PublicIdentity>[];
      if (mine.isEmpty) continue;
      final baseAngle = -pi / 2 + i * 2 * pi / max(brokers.length, 1);
      for (var p = 0; p < mine.length; p++) {
        final spread = (p - (mine.length - 1) / 2) * 0.34;
        final id = 'p:${mine[p].fingerprint}';
        nodes.add(_Node(
          id: id,
          label: mine[p].name,
          kind: _NodeKind.peer,
          at: _pinned[id] ??
              Offset(cos(baseAngle + spread), sin(baseAngle + spread)) *
                  (ringRadius * 1.75),
          peer: mine[p],
        ));
        edges.add(_Edge('b:${broker.name}', id));
      }
    }

    // People heard on a network that is no longer in the list still exist;
    // hang them off this device rather than dropping them off the map.
    for (final entry in byNetwork.entries) {
      if (brokers.any((b) => b.name == entry.key)) continue;
      for (var p = 0; p < entry.value.length; p++) {
        final id = 'p:${entry.value[p].fingerprint}';
        if (nodes.any((n) => n.id == id)) continue;
        final angle = p * 2 * pi / max(entry.value.length, 1);
        nodes.add(_Node(
          id: id,
          label: entry.value[p].name,
          kind: _NodeKind.peer,
          at: _pinned[id] ??
              Offset(cos(angle), sin(angle)) * (ringRadius * 0.55),
          peer: entry.value[p],
        ));
        edges.add(_Edge('@me', id));
      }
    }

    _nodes = nodes;
    _edges = edges;
  }

  // ----------------------------------------------------------- gestures

  Offset _toGraph(Offset screen) => (screen - _pan) / _scale;

  _Node? _nodeAt(Offset screen) {
    final point = _toGraph(screen);
    // Reverse order: the peers drawn last are the ones on top.
    for (final node in _nodes.reversed) {
      if ((node.at - point).distance <= node.radius + 6 / _scale) return node;
    }
    return null;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocal = details.localFocalPoint;
    _gestureStart = details.localFocalPoint;
    _movedDuringGesture = false;
    _scaleAtGestureStart = _scale;
    _dragging =
        details.pointerCount == 1 ? _nodeAt(details.localFocalPoint)?.id : null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if ((details.localFocalPoint - _gestureStart).distance > _tapSlop ||
        details.scale != 1.0) {
      _movedDuringGesture = true;
    }
    setState(() {
      if (_dragging != null && details.pointerCount == 1) {
        // Moving a node, not the map.
        final node = _nodes.firstWhere((n) => n.id == _dragging);
        node.at += (details.localFocalPoint - _lastFocal) / _scale;
        _pinned[node.id] = node.at;
        _lastFocal = details.localFocalPoint;
        return;
      }
      if (details.scale != 1.0) {
        // Zoom about the pinch centre, so what is under the fingers stays
        // under the fingers.
        final target = (_scaleAtGestureStart * details.scale).clamp(0.25, 4.0);
        final focal = details.localFocalPoint;
        _pan = focal - (focal - _pan) * (target / _scale);
        _scale = target;
      }
      _pan += details.localFocalPoint - _lastFocal;
      _lastFocal = details.localFocalPoint;
    });
  }

  void _zoomBy(double factor, Size size) {
    setState(() {
      final centre = Offset(size.width / 2, size.height / 2);
      final target = (_scale * factor).clamp(0.25, 4.0);
      _pan = centre - (centre - _pan) * (target / _scale);
      _scale = target;
    });
  }

  /// Puts every node back where the layout wants it and re-centres.
  void _resetLayout(Size size) {
    setState(() {
      _pinned.clear();
      _scale = 1;
      _pan = Offset(size.width / 2, size.height / 2);
    });
  }

  // --------------------------------------------------------------- info

  void _showNode(_Node node) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _nodeDetails(node, sheetContext),
        ),
      ),
    );
  }

  List<Widget> _nodeDetails(_Node node, BuildContext sheetContext) {
    switch (node.kind) {
      case _NodeKind.me:
        return [
          ListTile(
            leading: const Icon(Icons.smartphone_rounded),
            title: Text(node.label),
            subtitle: const Text('This device'),
          ),
          ListTile(
            leading: const Icon(Icons.hub_rounded),
            title: Text('${_brokers.brokers.length} networks, '
                '${_brokers.peers.length} people in sight'),
            subtitle: const Text(
                'Everything on this map was heard through those networks.'),
          ),
        ];

      case _NodeKind.broker:
        final broker = node.broker!;
        final connected = _brokers.isConnected(broker);
        return [
          ListTile(
            leading: Icon(
              connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              color: connected ? Colors.greenAccent : Colors.orangeAccent,
            ),
            title: Text(broker.name),
            subtitle: Text('${broker.host}:${broker.port}'),
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_rounded),
            title: Text('${_peersOn(broker.name)} people on this network'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.power_settings_new_rounded),
            title: Text(connected ? 'Connected' : 'Disconnected'),
            subtitle: Text(connected
                ? 'Turn off to leave this network.'
                : 'Turn on to join this network.'),
            value: connected,
            onChanged: (value) async {
              Navigator.pop(sheetContext);
              if (value) {
                await _brokers.setAutoConnect(broker, true);
                final ok = await _brokers.connect(broker);
                if (!ok && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('${broker.name} is not reachable.')));
                }
              } else {
                await _brokers.disconnect(broker);
                await _brokers.setAutoConnect(broker, false);
              }
            },
          ),
        ];

      case _NodeKind.peer:
        final peer = node.peer!;
        final network = _brokers.networkOf(peer.fingerprint);
        return [
          ListTile(
            leading: const Icon(Icons.verified_user_rounded),
            title: Text(peer.name),
            subtitle: Text(network.isEmpty
                ? 'Seen on the mesh'
                : 'Reachable through $network'),
          ),
          ListTile(
            leading: const Icon(Icons.key_rounded),
            title: const Text('Public key'),
            subtitle: Text(peer.fingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
          ListTile(
            leading: const Icon(Icons.call_rounded),
            title: const Text('Call'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final chat = await ChatService.instance.startDm(peer);
              if (!mounted) return;
              final error = await CallService.instance.call(chat);
              if (error != null) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
                return;
              }
              if (!mounted) return;
              Navigator.push(
                context,
                GlassPageRoute(page: CallPage(avatar: peer.avatar)),
              );
            },
          ),
        ];
    }
  }

  int _peersOn(String brokerName) => _brokers.peers
      .where((p) => _brokers.networkOf(p.fingerprint) == brokerName)
      .length;

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _rebuildGraph();
    final hasNetworks = _brokers.brokers.isNotEmpty;
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
              child: !hasNetworks
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
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final size = constraints.biggest;
                        // First frame: put the origin in the middle.
                        if (!_viewPlaced) {
                          _viewPlaced = true;
                          _pan = Offset(size.width / 2, size.height / 2);
                        }
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: _onScaleUpdate,
                                onScaleEnd: (_) {
                                  _dragging = null;
                                  if (_movedDuringGesture) return;
                                  final node = _nodeAt(_gestureStart);
                                  if (node != null) _showNode(node);
                                },
                                child: AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (context, _) => CustomPaint(
                                    painter: _GraphPainter(
                                      nodes: _nodes,
                                      edges: _edges,
                                      scale: _scale,
                                      pan: _pan,
                                      phase: _pulse.value,
                                      scheme: Theme.of(context).colorScheme,
                                    ),
                                    size: Size.infinite,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 12,
                              bottom: 12,
                              child: Column(
                                children: [
                                  _MapButton(
                                    icon: Icons.add_rounded,
                                    tooltip: 'Zoom in',
                                    onTap: () => _zoomBy(1.25, size),
                                  ),
                                  const SizedBox(height: 8),
                                  _MapButton(
                                    icon: Icons.remove_rounded,
                                    tooltip: 'Zoom out',
                                    onTap: () => _zoomBy(0.8, size),
                                  ),
                                  const SizedBox(height: 8),
                                  _MapButton(
                                    icon: Icons.center_focus_strong_rounded,
                                    tooltip: 'Reset the layout',
                                    onTap: () => _resetLayout(size),
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              left: 12,
                              bottom: 12,
                              child: LiquidGlass(
                                radius: 14,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                child: Text(
                                  'Drag a node to move it · tap for details',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            LiquidGlass(
              margin: const EdgeInsets.all(12),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
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

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      radius: 22,
      padding: EdgeInsets.zero,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon),
        onPressed: onTap,
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
    required this.nodes,
    required this.edges,
    required this.scale,
    required this.pan,
    required this.phase,
    required this.scheme,
  });

  final List<_Node> nodes;
  final List<_Edge> edges;
  final double scale;
  final Offset pan;
  final double phase;
  final ColorScheme scheme;

  Offset _toScreen(Offset graph) => graph * scale + pan;

  @override
  void paint(Canvas canvas, Size size) {
    final onSurface = scheme.onSurface;
    final byId = {for (final node in nodes) node.id: node};

    for (var i = 0; i < edges.length; i++) {
      final from = byId[edges[i].from];
      final to = byId[edges[i].to];
      if (from == null || to == null) continue;
      final a = _toScreen(from.at);
      final b = _toScreen(to.at);
      final live = edges[i].live;
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = (live ? Colors.greenAccent : to.color)
              .withValues(alpha: live ? 0.75 : 0.4)
          ..strokeWidth = (live ? 2.4 : 1.2) * scale.clamp(0.5, 1.5)
          ..style = PaintingStyle.stroke,
      );
      if (live) {
        // A dot travelling along the link makes a working path legible.
        final t = (phase + i / max(edges.length, 1)) % 1.0;
        canvas.drawCircle(
          Offset.lerp(a, b, t)!,
          3 * scale.clamp(0.6, 1.6),
          Paint()..color = Colors.greenAccent.withValues(alpha: 1 - t),
        );
      }
    }

    // The halo marks the centre without needing a label to say so.
    final me = byId['@me'];
    if (me != null) {
      canvas.drawCircle(
        _toScreen(me.at),
        (34 + 6 * sin(phase * 2 * pi)) * scale,
        Paint()..color = scheme.primary.withValues(alpha: 0.18),
      );
    }

    for (final node in nodes) {
      final at = _toScreen(node.at);
      final radius = node.radius * scale;
      final color =
          node.kind == _NodeKind.me ? scheme.primary : node.color;
      canvas.drawCircle(
          at, radius, Paint()..color = color.withValues(alpha: 0.22));
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * scale.clamp(0.5, 1.5),
      );
      final icon = switch (node.kind) {
        _NodeKind.me => Icons.smartphone_rounded,
        _NodeKind.broker => node.connected
            ? Icons.cloud_done_rounded
            : Icons.cloud_off_rounded,
        _NodeKind.peer => null,
      };
      if (icon != null) {
        _icon(canvas, at, radius, icon, color);
      } else {
        _label(
          canvas,
          at,
          node.label.isEmpty ? '?' : node.label[0].toUpperCase(),
          onSurface,
          radius * 0.9,
          centred: true,
        );
      }
      _label(
        canvas,
        at + Offset(0, radius + 8),
        node.label,
        onSurface.withValues(alpha: node.kind == _NodeKind.peer ? 0.75 : 1),
        (node.kind == _NodeKind.peer ? 10 : 11) * scale.clamp(0.7, 1.4),
      );
    }
  }

  void _icon(
      Canvas canvas, Offset centre, double radius, IconData icon, Color color) {
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
    builder.paint(
        canvas, centre - Offset(builder.width / 2, builder.height / 2));
  }

  void _label(Canvas canvas, Offset at, String text, Color color, double size,
      {bool centred = false}) {
    if (size < 4) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140);
    painter.paint(
      canvas,
      at - Offset(painter.width / 2, centred ? painter.height / 2 : 0),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
