import 'dart:convert';
import 'dart:typed_data';

import 'package:chatnyto/devices/adb/adb_client.dart';
import 'package:chatnyto/devices/adb/adb_key.dart';
import 'package:chatnyto/devices/adb/adb_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the wire format', () {
    test('a header is 24 bytes and the payload follows it', () {
      final message = AdbMessage(AdbMessage.connect, 0x01000001, 256 * 1024,
          Uint8List.fromList(utf8.encode('host::')));
      expect(message.encode().length, 24 + 6);
    });

    test('the magic is the command with every bit flipped', () {
      // It is how a reader tells a header from the middle of a payload, and
      // getting it wrong makes adbd close the connection without a word.
      final encoded = AdbMessage(AdbMessage.open, 1, 0, Uint8List(0)).encode();
      final view = ByteData.sublistView(encoded);
      expect(view.getUint32(0, Endian.little), AdbMessage.open);
      expect(view.getUint32(20, Endian.little),
          (AdbMessage.open ^ 0xffffffff) & 0xffffffff);
    });

    test('the checksum is a plain sum of the bytes', () {
      // Called a CRC everywhere it is described, and it is not one.
      expect(AdbMessage.checksumOf(Uint8List.fromList([1, 2, 3])), 6);
      expect(AdbMessage.checksumOf(Uint8List.fromList([255, 255])), 510);
      expect(AdbMessage.checksumOf(Uint8List(0)), 0);
    });

    test('a header with the wrong magic is rejected', () {
      final bytes = AdbMessage(AdbMessage.okay, 1, 2, Uint8List(0)).encode();
      expect(AdbMessage.headerIsSane(bytes), isTrue);
      bytes[20] ^= 0xff;
      expect(AdbMessage.headerIsSane(bytes), isFalse);
    });

    test('a truncated header is not a header', () {
      expect(AdbMessage.headerIsSane(Uint8List(12)), isFalse);
    });

    test('the four commands spell what they should', () {
      // Each is four ASCII characters little-endian, and a typo would be
      // silently ignored by the device rather than reported.
      String spell(int command) => String.fromCharCodes([
            command & 0xff,
            (command >> 8) & 0xff,
            (command >> 16) & 0xff,
            (command >> 24) & 0xff,
          ]);
      expect(spell(AdbMessage.connect), 'CNXN');
      expect(spell(AdbMessage.auth), 'AUTH');
      expect(spell(AdbMessage.open), 'OPEN');
      expect(spell(AdbMessage.okay), 'OKAY');
      expect(spell(AdbMessage.close), 'CLSE');
      expect(spell(AdbMessage.write), 'WRTE');
    });
  });

  group('reading what a computer says about its devices', () {
    test('a line of adb devices -l becomes a device', () {
      final device = AdbDevice.parse(
          'R58M42ABCDE            device product:a12 model:SM_A125F '
          'device:a12 transport_id:3')!;
      expect(device.serial, 'R58M42ABCDE');
      expect(device.state, 'device');
      expect(device.model, 'SM_A125F');
      expect(device.usable, isTrue);
      // Underscores are how the model comes off the wire, not how anybody
      // wants to read it.
      expect(device.label, 'SM A125F');
    });

    test('an unauthorised device is listed, not hidden', () {
      // It is exactly the case the user needs to see: the answer is on the
      // other device's screen.
      final device = AdbDevice.parse('emulator-5554 unauthorized')!;
      expect(device.usable, isFalse);
      expect(device.state, 'unauthorized');
    });

    test('a device with no model falls back to its serial', () {
      expect(AdbDevice.parse('1234abcd device')!.label, '1234abcd');
    });

    test('the header line is not a device', () {
      expect(AdbDevice.parse('List of devices attached'), isNull);
    });

    test('a line with nothing on it is not a device', () {
      expect(AdbDevice.parse('orphan'), isNull);
    });
  });

  group('saved connections', () {
    test('a device and a computer have different default ports', () {
      // 5555 is adbd on a device; 5037 is the server a computer runs. They
      // speak different protocols, and offering the wrong port is the
      // easiest way to make either look broken.
      expect(AdbTarget.defaultPort(AdbTargetKind.device), 5555);
      expect(AdbTarget.defaultPort(AdbTargetKind.computer), 5037);
    });

    test('a target survives a round trip', () {
      final target = AdbTarget(
        id: 'adb-1',
        name: 'Living room',
        host: '192.168.1.42',
        port: 5555,
        kind: AdbTargetKind.device,
      );
      final back = AdbTarget.fromJson(
          jsonDecode(jsonEncode(target.toJson())) as Map<String, dynamic>)!;
      expect(back.name, 'Living room');
      expect(back.address, '192.168.1.42:5555');
      expect(back.kind, AdbTargetKind.device);
    });

    test('an entry with no id is not a target', () {
      expect(AdbTarget.fromJson({'host': 'nowhere'}), isNull);
    });

    test('an unknown kind reads as a device rather than breaking the list',
        () {
      final back = AdbTarget.fromJson({'id': 'x', 'kind': 'mainframe'})!;
      expect(back.kind, AdbTargetKind.device);
    });
  });

  _keyBlobTests();
}

/// A 2048-bit odd number standing in for a modulus. The arithmetic below
/// does not care that it is not a product of two primes; it cares that it is
/// the right width and odd, which every RSA modulus is.
final _modulus = (BigInt.one << 2047) + BigInt.from(0x9f2b);

void _keyBlobTests() {
  group('the key adbd is shown', () {
    test('the structure is exactly 524 bytes', () {
      // Four fields and two 256-byte numbers. adbd reads a fixed size and
      // does not check; a byte out either way is a key it silently refuses.
      expect(AdbKey.publicKeyBlob(_modulus, BigInt.from(65537)).length, 524);
    });

    test('n0inv really is -1/n mod 2^32', () {
      // The verifier multiplies by this to avoid a division. If it is wrong
      // every signature this app makes is rejected, with no message anywhere
      // saying why.
      final base = BigInt.one << 32;
      final n0inv = BigInt.from(AdbKey.n0inv(_modulus));
      final n0 = _modulus % base;
      expect((n0 * n0inv) % base, base - BigInt.one);
    });

    test('the modulus is stored little-endian', () {
      final blob = AdbKey.publicKeyBlob(_modulus, BigInt.from(65537));
      // Byte 8 is the least significant byte of n, not the most.
      expect(blob[8], (_modulus & BigInt.from(0xff)).toInt());
      expect(blob[8 + 255], (_modulus >> (8 * 255)).toInt() & 0xff);
    });

    test('rr is 2^4096 mod n, where the verifier expects it', () {
      final blob = AdbKey.publicKeyBlob(_modulus, BigInt.from(65537));
      var rebuilt = BigInt.zero;
      for (var i = 255; i >= 0; i--) {
        rebuilt = (rebuilt << 8) + BigInt.from(blob[264 + i]);
      }
      expect(rebuilt, (BigInt.one << 4096) % _modulus);
    });

    test('the exponent is the last four bytes', () {
      final blob = AdbKey.publicKeyBlob(_modulus, BigInt.from(65537));
      final view = ByteData.sublistView(blob);
      expect(view.getUint32(520, Endian.little), 65537);
      expect(view.getUint32(0, Endian.little), 64);
    });
  });
}
