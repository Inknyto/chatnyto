import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/chat_message.dart';

class MessageStorage {
  Future<void> saveMessages(List<ChatMessage> messages, String brokerIP, String topicName) async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = messages.map((msg) => jsonEncode(msg.toJson())).toList();
    await prefs.setStringList('$brokerIP:$topicName', messagesJson);
  }

  Future<List<ChatMessage>> loadMessages(String brokerIP, String topicName) async {
    final prefs = await SharedPreferences.getInstance();
    final messagesJson = prefs.getStringList('$brokerIP:$topicName') ?? [];
    return messagesJson.map((json) => ChatMessage.fromJson(jsonDecode(json))).toList();
  }
}
