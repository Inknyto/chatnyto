import 'dart:io';
import 'dart:typed_data';

import 'packet_handler.dart';

class MQTTBroker {
  final int port;
  final Map<String, List<Socket>> subscriptions = {};

  MQTTBroker(this.port) {
    _startServer();
  }

  void _startServer() {
    ServerSocket.bind(InternetAddress.anyIPv4, port).then((serverSocket) {
      print('MQTT Broker started on port $port');
      serverSocket.listen(_handleConnection);
    });
  }

  void _handleConnection(Socket socket) {
    socket.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: true,
    );
  }

  void _handleData(Uint8List data) {
    final packet = PacketHandler.parsePacket(data);
    PacketHandler.handlePacket(packet, this);
  }

  void _handleError(Object error) {
    print('Error: $error');
  }

  void _handleDone() {
    print('Client disconnected');
  }

  void _publishMessage(String topic, Uint8List message) {
    final subscribers = subscriptions[topic];
    if (subscribers != null) {
      for (final socket in subscribers) {
        socket.add(message);
      }
    }
  }

  void subscribe(String topic, Socket socket) {
    subscriptions.putIfAbsent(topic, () => []).add(socket);
  }

  void unsubscribe(String topic, Socket socket) {
    subscriptions[topic]?.remove(socket);
  }
}
