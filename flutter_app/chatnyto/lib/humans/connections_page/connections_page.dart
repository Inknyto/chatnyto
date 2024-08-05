// connections_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
            children: [
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
            onLongPress: () => {
              setState(() {
                _connections.remove(connection);
                _saveConnections();
              })
            },
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
