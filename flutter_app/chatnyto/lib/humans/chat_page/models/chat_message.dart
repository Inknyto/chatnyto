import 'package:flutter_quill/flutter_quill.dart' as quill;

class ChatMessage {
  final String sender;
  final List<dynamic> delta;
  final int timestamp; // milliseconds since epoch

  ChatMessage({
    required this.sender,
    required this.delta,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      sender: json['sender'],
      delta: json['delta'],
      timestamp: json['ts'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sender': sender,
      'delta': delta,
      'ts': timestamp,
    };
  }

  quill.Document toDocument() {
    return quill.Document.fromJson(delta);
  }

  String get timeLabel {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
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
