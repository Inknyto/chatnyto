import 'package:flutter_quill/flutter_quill.dart' as quill;

class ChatMessage {
  final String sender;
  final List<dynamic> delta;

  ChatMessage({required this.sender, required this.delta});

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      sender: json['sender'],
      delta: json['delta'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'delta': delta,
    };
  }

  quill.Document toDocument() {
    return quill.Document.fromJson(delta);
  }
}
