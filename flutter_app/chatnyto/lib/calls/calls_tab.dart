import 'package:flutter/material.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import '../core/widgets/liquid_glass.dart';
import '../revamp/chat_service.dart';
import 'call_page.dart';
import 'call_service.dart';

/// Recent calls, and a way to start one — the clone's Calls screen, on top
/// of ChatNyto's own peer-to-peer calling.
class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab> {
  final CallService _calls = CallService.instance;

  @override
  void initState() {
    super.initState();
    _calls.init();
    _calls.addListener(_onChanged);
  }

  @override
  void dispose() {
    _calls.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Calls a verified peer, opening the call screen while it rings.
  Future<void> _startCall(PublicIdentity peer) async {
    final chat = await ChatService.instance.startDm(peer);
    final error = await _calls.call(chat);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.push(
      context,
      GlassPageRoute(page: CallPage(avatar: peer.avatar)),
    );
  }

  Future<void> _pickSomeone() async {
    final peers = BrokerService.instance.peers.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final myFp = IdentityService.instance.isUnlocked
        ? (await IdentityService.instance.publicIdentity()).fingerprint
        : '';
    final callable = peers.where((p) => p.fingerprint != myFp).toList();
    if (!mounted) return;
    final peer = await showModalBottomSheet<PublicIdentity>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: callable.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Nobody is reachable right now. Calls need both devices on '
                  'the same network — the LoRa box only carries messages.',
                  textAlign: TextAlign.center,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final peer in callable)
                    ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: Text(peer.name),
                      subtitle: Text(peer.fingerprint,
                          style: const TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.call_rounded),
                      onTap: () => Navigator.pop(sheetContext, peer),
                    ),
                ],
              ),
      ),
    );
    if (peer != null) await _startCall(peer);
  }

  /// Calls someone back from the history, if they are still visible.
  Future<void> _callBack(CallRecord record) async {
    final peer = BrokerService.instance.peers
        .where((p) => p.fingerprint == record.peerFingerprint)
        .cast<PublicIdentity?>()
        .firstWhere((p) => true, orElse: () => null);
    if (peer == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${record.peerName} is not on the network now.')),
      );
      return;
    }
    await _startCall(peer);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final records = _calls.history;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: records.isEmpty
          ? const Center(
              child: LiquidGlass(
                margin: EdgeInsets.all(24),
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_rounded, size: 44),
                    SizedBox(height: 12),
                    Text(
                      'No calls yet',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Voice calls go straight between the two devices, '
                      'encrypted end to end, with no server in the middle. '
                      'Both of you need to be on the same network.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final icon = record.missed
                    ? Icons.call_missed_rounded
                    : (record.outgoing
                        ? Icons.call_made_rounded
                        : Icons.call_received_rounded);
                final color = record.missed
                    ? Colors.redAccent
                    : scheme.onSurface.withValues(alpha: 0.6);
                return LiquidGlass(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Text(
                        record.peerName.isEmpty
                            ? '?'
                            : record.peerName[0].toUpperCase(),
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                    title: Text(
                      record.peerName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: record.missed ? Colors.redAccent : null,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          '${_when(record.startedAt)} · '
                          '${record.durationLabel}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.call_rounded),
                      onPressed: () => _callBack(record),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickSomeone,
        tooltip: 'New call',
        child: const Icon(Icons.add_ic_call_rounded),
      ),
    );
  }

  String _when(int ts) {
    final time = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final hhmm = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return hhmm;
    }
    return '${time.day}/${time.month} $hhmm';
  }
}
