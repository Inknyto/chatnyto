import 'package:flutter/material.dart';

import '../../core/brokers/broker_service.dart';
import '../../core/widgets/liquid_glass.dart';

/// Explore page: a newsfeed of the people discovered on the connected
/// brokers through their signed presence advertisements.
class HeatMapPage extends StatefulWidget {
  const HeatMapPage({super.key});

  @override
  State<HeatMapPage> createState() => _HeatMapPageState();
}

class _HeatMapPageState extends State<HeatMapPage> {
  final BrokerService _service = BrokerService.instance;

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

  @override
  Widget build(BuildContext context) {
    final peers = _service.peers;
    final connectedCount =
        _service.brokers.where(_service.isConnected).length;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Explore')),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            LiquidGlass(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: const Icon(Icons.radar_rounded),
                title: Text('$connectedCount broker(s) connected'),
                subtitle: Text(peers.isEmpty
                    ? 'Connect to a broker (menu → Brokers) to discover '
                        'people around you.'
                    : '${peers.length} people advertising on the network'),
              ),
            ),
            for (final peer in peers)
              LiquidGlass(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(peer.name.isEmpty
                        ? '?'
                        : peer.name[0].toUpperCase()),
                  ),
                  title: Text(peer.name),
                  subtitle: Text('Verified key ${peer.fingerprint}'),
                  trailing: const Icon(Icons.verified_rounded,
                      color: Colors.greenAccent),
                ),
              ),
            if (peers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: GlassShimmer(count: 4),
              ),
          ],
        ),
      ),
    );
  }
}
