import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ChatBotPage extends StatefulWidget {
  const ChatBotPage({super.key});

  @override
  State<ChatBotPage> createState() => _ChatBotPageState();
}

class _ChatBotPageState extends State<ChatBotPage> {
  final TextEditingController _textController = TextEditingController();
  final List<String> _messages = [];

  Future<void> _sendMessage(String message) async {
    _messages.add('User: $message');
    _messages.add('\n\n');
    setState(() {});

    try {
      final request =
          http.Request('POST', Uri.parse('http://127.0.0.1:3000/send'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'message': message});

      final response = await request.send();

      if (response.statusCode == 200) {
        final stream = response.stream.transform(utf8.decoder);
        _messages.add('Chatbot: ');
        await for (final data in stream) {
          _messages.add(data);
          setState(() {});
        }
      } else {
        _messages.add('An error occurred during chatbot processing.');
        setState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatnyto Bot'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Wrap(
              children: _messages
                  .map(
                    (message) => Text(
                      message,
                      style: const TextStyle(color: Colors.black, fontSize: 16),
                    ),
                  )
                  .toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    hintText: 'It was a dark and stormy night...',
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  final message = _textController.text.trim();
                  if (message.isNotEmpty) {
                    _textController.clear();
                    _sendMessage(message);
                  }
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
