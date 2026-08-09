import 'package:chatnyto/core/brokers/broker_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which addresses a network is tried at, and in what order.
///
/// This is the difference between a phone that joins a published server and
/// one that cannot: typing `supa-tech.com` used to mean plain MQTT on 1883,
/// a port such a server has shut, so the connection could never succeed no
/// matter how long it retried.
void main() {
  group('a bare hostname', () {
    final ladder = BrokerService.addressLadder(
      Broker(name: 'vps', host: 'broker.supa-tech.com'),
    );

    test('is tried over WebSockets before anything else', () {
      expect(ladder.first, 'wss://broker.supa-tech.com/mqtt:443');
    });

    test('covers both the conventional path and the bare origin', () {
      // /mqtt is the convention; / is what a tunnel mapped to the whole
      // origin gives you, and the deployed server is the second kind.
      expect(ladder[0], contains('/mqtt'));
      expect(ladder[1], 'wss://broker.supa-tech.com/:443');
    });

    test('falls back to TLS and then to plain MQTT', () {
      expect(ladder[2], 'broker.supa-tech.com:8883');
      expect(ladder[3], 'broker.supa-tech.com:1883');
    });
  });

  group('an address the user was explicit about', () {
    test('a typed scheme is an instruction, not a guess', () {
      expect(
        BrokerService.addressLadder(
          Broker(name: 'v', host: 'mqtt://example.com'),
        ),
        ['example.com:1883'],
      );
    });

    test('a chosen port is respected rather than laddered past', () {
      expect(
        BrokerService.addressLadder(
          Broker(name: 'v', host: 'example.com', port: 8883),
        ),
        ['example.com:8883'],
      );
    });
  });

  group('a local broker', () {
    test('an IP is plain MQTT and is not probed on 443', () {
      // A LoRa or LAN broker has no certificate and no HTTPS front door.
      // Probing one costs seconds per sweep and can never succeed.
      expect(
        BrokerService.addressLadder(Broker(name: 'lora', host: '192.168.4.1')),
        ['192.168.4.1:1883'],
      );
    });

    test('a bare name with no dot is local too', () {
      expect(
        BrokerService.addressLadder(Broker(name: 'pi', host: 'raspberrypi')),
        ['raspberrypi:1883'],
      );
    });
  });
}
