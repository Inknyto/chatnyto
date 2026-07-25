// connections_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/liquid_glass.dart';
import '../../core/widgets/wa_components.dart';
import '../chat_page/chat_page.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final List<Map<String, String>> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson = prefs.getStringList('connections') ?? [];
    setState(() {
      _connections.clear();
      _connections.addAll(connectionsJson
          .map((json) => Map<String, String>.from(jsonDecode(json))));
    });
  }

  Future<void> _saveConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final connectionsJson =
        _connections.map((connection) => jsonEncode(connection)).toList();
    print(connectionsJson);
    await prefs.setStringList('connections', connectionsJson);
  }

  void _addConnection() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        String brokerIP = '';
        String topicName = '';
        String secret = '';

        return AlertDialog(
          title: const Text('Add New Connection'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How to join: ask the other person (or group owner) for '
                  'the broker address, the topic name, and — for a private '
                  'channel — the shared passphrase. Everyone using the same '
                  'three values ends up in the same encrypted chat.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Broker IP / hostname',
                  ),
                  onChanged: (value) {
                    brokerIP = value;
                  },
                ),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Topic Name',
                  ),
                  onChanged: (value) {
                    topicName = value;
                  },
                ),
                TextField(
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Channel passphrase (optional)',
                    helperText: 'Set for a private end-to-end encrypted channel',
                  ),
                  onChanged: (value) {
                    secret = value;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (brokerIP.isNotEmpty && topicName.isNotEmpty) {
                  setState(() {
                    _connections.add({
                      'brokerIP': brokerIP,
                      'topicName': topicName,
                      'secret': secret,
                    });
                  });
                  _saveConnections(); // Save connections after adding a new one
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _navigateToChat(Map<String, String> connection) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          brokerIP: connection['brokerIP']!,
          topicName: connection['topicName']!,
          channelSecret: connection['secret'] ?? '',
          deviceIP: '', // You can pass an empty string here
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            'ChatNyto',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              onPressed: _addConnection,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              onPressed: _addConnection,
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ],
        ),
        body: _connections.isEmpty
            ? const Center(
                child: LiquidGlass(
                  margin: EdgeInsets.all(24),
                  padding: EdgeInsets.all(20),
                  child: Text(
                      'No chats yet.\nTap the button below to join one.',
                      textAlign: TextAlign.center),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _connections.length,
                itemBuilder: (context, index) {
                  final connection = _connections[index];
                  final private = (connection['secret'] ?? '').isNotEmpty;
                  return WaChatTile(
                    title: connection['topicName'] ?? '',
                    subtitle:
                        '${private ? "🔒 " : ""}on ${connection['brokerIP']}',
                    onTap: () => _navigateToChat(connection),
                    onLongPress: () => setState(() {
                      _connections.remove(connection);
                      _saveConnections();
                    }),
                  );
                },
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: _addConnection,
          child: const Icon(Icons.message_rounded),
        ),
      ),
    );
  }
}
