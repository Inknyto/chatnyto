import 'package:flutter/material.dart';

import '../brokers/broker_service.dart';

/// Live "connected / disconnected" indicator, the way the classic ChatNyto
/// screens showed it — a dot plus a word, kept in sync with the brokers.
class ConnectionStatusChip extends StatefulWidget {
  const ConnectionStatusChip({super.key, this.compact = false});

  /// Dot only, for tight places like an app bar.
  final bool compact;

  @override
  State<ConnectionStatusChip> createState() => _ConnectionStatusChipState();
}

class _ConnectionStatusChipState extends State<ConnectionStatusChip> {
  final BrokerService _brokers = BrokerService.instance;

  @override
  void initState() {
    super.initState();
    _brokers.addListener(_onChanged);
  }

  @override
  void dispose() {
    _brokers.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final connected = _brokers.brokers.where(_brokers.isConnected).length;
    final online = connected > 0;
    final color = online ? Colors.greenAccent : Colors.orangeAccent;
    final label = online
        ? (connected == 1 ? 'connected' : 'connected · $connected networks')
        : 'disconnected';
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.6), blurRadius: 6),
        ],
      ),
    );
    if (widget.compact) {
      return Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: dot,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
          ),
        ),
      ],
    );
  }
}
