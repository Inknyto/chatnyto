import 'dart:typed_data';

import 'mqtt_broker.dart';
import 'packet_types.dart';

class PacketHandler {
  static Packet parsePacket(Uint8List data) {
    // Parse the incoming data as an MQTT packet
    // Implement your packet parsing logic here
    // Return a Packet object with the appropriate type and data
    return Packet(PacketType.connect, data);
  }

  static void handlePacket(Packet packet, MQTTBroker broker) {
    switch (packet.type) {
      case PacketType.connect:
        // Handle CONNECT packet
        break;
      case PacketType.subscribe:
        // Handle SUBSCRIBE packet
        final topic = packet.data.toString();
        final socket = packet.socket!;
        broker.subscribe(topic, socket);
        break;
      case PacketType.publish:
        // Handle PUBLISH packet
        final topic = packet.topic!;
        final message = packet.data;
        broker._publishMessage(topic, message);
        break;
      case PacketType.unsubscribe:
        // Handle UNSUBSCRIBE packet
        final topic = packet.data.toString();
        final socket = packet.socket!;
        broker.unsubscribe(topic, socket);
        break;
      case PacketType.disconnect:
        // Handle DISCONNECT packet
        break;
    }
  }
}

class Packet {
  final PacketType type;
  final Uint8List data;
  final String? topic;
  final Socket? socket;

  Packet(this.type, this.data, {this.topic, this.socket});
}
