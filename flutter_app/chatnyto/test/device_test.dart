import 'dart:convert';

import 'package:chatnyto/devices/device.dart';
import 'package:chatnyto/devices/device_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('where a control publishes', () {
    test('a bare name goes under the app own device tree', () {
      // Which is the subtree the broker ACL grants signed-in users, and the
      // only place a control can publish without the broker refusing it.
      expect(DeviceService.fullTopic('kitchen/light'),
          'chatnyto/devices/kitchen/light');
    });

    test('a leading slash means an absolute topic', () {
      // Hardware that was already publishing somewhere before this app
      // existed does not get to be moved.
      expect(DeviceService.fullTopic('/home/sensors/temp'),
          'home/sensors/temp');
    });

    test('surrounding space is not part of a topic', () {
      expect(DeviceService.fullTopic('  lamp  '), 'chatnyto/devices/lamp');
    });
  });

  group('storing what the user configured', () {
    final device = Device(
      id: 'dev-1',
      name: 'Workshop',
      kind: DeviceKind.mqtt,
      room: 'Garage',
      controls: [
        DeviceControl(
          name: 'Lamp',
          kind: ControlKind.toggle,
          topic: 'workshop/lamp',
          onPayload: '1',
          offPayload: '0',
        ),
        DeviceControl(
          name: 'Temperature',
          kind: ControlKind.reading,
          topic: '/sensors/workshop',
          unit: '°C',
        ),
      ],
    );

    test('survives a round trip through storage', () {
      final back = Device.fromJson(
          jsonDecode(jsonEncode(device.toJson())) as Map<String, dynamic>)!;
      expect(back.name, 'Workshop');
      expect(back.kind, DeviceKind.mqtt);
      expect(back.room, 'Garage');
      expect(back.controls.length, 2);
      expect(back.controls.first.onPayload, '1');
      expect(back.controls.last.unit, '°C');
      expect(back.controls.last.kind, ControlKind.reading);
    });

    test('an entry with no id is not a device', () {
      expect(Device.fromJson({'name': 'nameless'}), isNull);
    });

    test('an unknown kind falls back to MQTT rather than throwing', () {
      // A device written by a newer build must not make the list unreadable.
      final back = Device.fromJson({'id': 'x', 'kind': 'holodeck'})!;
      expect(back.kind, DeviceKind.mqtt);
    });
  });

  group('a television', () {
    test('each protocol knows its own port', () {
      expect(DeviceKind.roku.defaultPort, 8060);
      expect(DeviceKind.samsungTv.defaultPort, 8002);
      expect(DeviceKind.lgTv.defaultPort, 3000);
      expect(DeviceKind.androidTv.defaultPort, 5555);
    });

    test('an MQTT device is not one', () {
      expect(DeviceKind.mqtt.isTelevision, isFalse);
      expect(DeviceKind.samsungTv.isTelevision, isTrue);
    });
  });

  group('ids', () {
    test('two devices added in a row do not collide', () async {
      final first = DeviceService.newId();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      expect(DeviceService.newId(), isNot(first));
    });
  });
}
