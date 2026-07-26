// connections_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/widgets/liquid_glass.dart';
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

        return AlertDialog(
          title: const Text('Add New Connection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How to join: every entity (friend, robot or AI) is reached '
                'the same way — the address of the broker it listens on and '
                'its topic name. Ask the owner for these two values.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Broker IP',
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
            ],
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


  /// Long-press edit mode: edit the connection in place or delete it.
  void _showConnectionOptions(Map<String, String> connection) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => LiquidGlass(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editConnection(connection);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _connections.remove(connection);
                  _saveConnections();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editConnection(Map<String, String> connection) {
    final brokerController =
        TextEditingController(text: connection['brokerIP']);
    final topicController =
        TextEditingController(text: connection['topicName']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: brokerController,
              decoration:
                  const InputDecoration(labelText: 'Broker IP / hostname'),
            ),
            TextField(
              controller: topicController,
              decoration: const InputDecoration(labelText: 'Topic Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (brokerController.text.isNotEmpty &&
                  topicController.text.isNotEmpty) {
                setState(() {
                  connection['brokerIP'] = brokerController.text.trim();
                  connection['topicName'] = topicController.text.trim();
                });
                _saveConnections();
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _navigateToChat(Map<String, String> connection) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          brokerIP: connection['brokerIP']!,
          topicName: connection['topicName']!,
          deviceIP: '', // You can pass an empty string here
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
      ),
      body: ListView.builder(
        itemCount: _connections.length,
        itemBuilder: (context, index) {
          final connection = _connections[index];
          return ListTile(
            title:
                Text('${connection['brokerIP']} - ${connection['topicName']}'),
            onTap: () => _navigateToChat(connection),
            onLongPress: () => _showConnectionOptions(connection),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: _addConnection,
      ),
    );
  }
}
