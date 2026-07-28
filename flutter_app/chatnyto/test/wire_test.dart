import 'dart:math';
import 'dart:typed_data';

import 'package:chatnyto/calls/voice_relay.dart';
import 'package:chatnyto/core/brokers/broker_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two pieces of new wire format that are easy to get subtly wrong and
/// impossible to eyeball: the nibble packing in the voice codec, and putting
/// a split message back together.
void main() {
  group('ADPCM', () {
    test('a round trip stays close to the original', () {
      // A tone rather than noise: ADPCM predicts a smooth signal well, and a
      // codec that mangles the packing shows up immediately as a poor match.
      final samples = Int16List(480);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (12000 * sin(2 * pi * 440 * i / 8000)).round();
      }

      final frame = AdpcmEncoder().encode(samples);
      final decoded = AdpcmDecoder().decode(frame);

      expect(decoded.lengthInBytes, samples.length * 2);

      // Measured after the first 120 samples. ADPCM starts every frame from
      // silence with the smallest step size and has to climb to the signal;
      // over the 15 ms that takes, the error is large and unavoidable, and
      // averaging it in would say more about the ramp than about the codec.
      var signal = 0.0;
      var noise = 0.0;
      for (var i = 120; i < samples.length; i++) {
        final out = decoded.getInt16(i * 2, Endian.host);
        signal += samples[i] * samples[i].toDouble();
        noise += (samples[i] - out) * (samples[i] - out).toDouble();
      }
      // Once it has caught up, IMA ADPCM is good for a little over 20 dB.
      // A broken packing or a lost sign bit lands far below zero.
      final snr = 10 * (log(signal / noise) / ln10);
      expect(snr, greaterThan(20), reason: 'steady-state SNR was $snr dB');
    });

    test('the encoder catches up with the signal within a few milliseconds',
        () {
      final samples = Int16List.fromList(List.filled(480, 10000));
      final decoded = AdpcmDecoder().decode(AdpcmEncoder().encode(samples));
      // From silence to full scale: the step size doubles its way up, so
      // this is quick. If it were not, every frame would start with a click.
      var caughtUpAt = -1;
      for (var i = 0; i < 480; i++) {
        if ((decoded.getInt16(i * 2, Endian.host) - 10000).abs() < 500) {
          caughtUpAt = i;
          break;
        }
      }
      expect(caughtUpAt, isNonNegative);
      expect(caughtUpAt, lessThan(120));
    });

    test('a frame is four times smaller than the samples', () {
      final frame = AdpcmEncoder().encode(Int16List(480));
      // 480 nibbles plus the three-byte predictor header.
      expect(frame.length, 240 + 3);
    });

    test('silence stays silent', () {
      final loud = Int16List.fromList(List.filled(480, 20000));
      final frame = AdpcmEncoder().encode(loud, silent: true);
      final decoded = AdpcmDecoder().decode(frame);
      for (var i = 0; i < 480; i++) {
        expect(decoded.getInt16(i * 2, Endian.host).abs(), lessThan(400));
      }
    });

    test('a decoder starting mid-stream still tracks the sender', () {
      // What makes a dropped frame cost 60 ms rather than the rest of the
      // call: every frame carries the state it was encoded from.
      final encoder = AdpcmEncoder();
      final samples = Int16List(480);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (9000 * sin(2 * pi * 300 * i / 8000)).round();
      }
      encoder.encode(samples); // sent, and lost on the way
      final second = encoder.encode(samples);

      final fresh = AdpcmDecoder().decode(second);
      expect(fresh.lengthInBytes, samples.length * 2);
      var worst = 0;
      for (var i = 0; i < samples.length; i++) {
        final delta = (samples[i] - fresh.getInt16(i * 2, Endian.host)).abs();
        if (delta > worst) worst = delta;
      }
      expect(worst, lessThan(4000));
    });
  });

  group('chunking', () {
    final service = BrokerService.instance;

    test('a large payload survives being split and put back together', () {
      final payload = List.generate(9000, (i) => 'abcdefghij'[i % 10]).join();
      final pieces = BrokerService.chunksFor(payload, 'x1');

      expect(pieces.length, 5); // 9000 bytes at 2048 a piece
      String? whole;
      for (final piece in pieces) {
        whole = service.collectChunk(piece);
      }
      expect(whole, payload);
    });

    test('nothing is returned until the last piece arrives', () {
      final payload = 'y' * 5000;
      final pieces = BrokerService.chunksFor(payload, 'x2');
      for (final piece in pieces.take(pieces.length - 1)) {
        expect(service.collectChunk(piece), isNull);
      }
      expect(service.collectChunk(pieces.last), payload);
    });

    test('pieces that arrive out of order still reassemble', () {
      final payload = 'z' * 7000;
      final pieces = BrokerService.chunksFor(payload, 'x3').reversed.toList();
      String? whole;
      for (final piece in pieces) {
        whole = service.collectChunk(piece);
      }
      expect(whole, payload);
    });

    test('two messages in flight at once do not mix', () {
      final first = 'a' * 5000;
      final second = 'b' * 5000;
      final one = BrokerService.chunksFor(first, 'x4');
      final two = BrokerService.chunksFor(second, 'x5');
      String? doneOne;
      String? doneTwo;
      for (var i = 0; i < one.length; i++) {
        doneOne = service.collectChunk(one[i]) ?? doneOne;
        doneTwo = service.collectChunk(two[i]) ?? doneTwo;
      }
      expect(doneOne, first);
      expect(doneTwo, second);
    });

    test('a malformed piece is ignored rather than trusted', () {
      expect(service.collectChunk({'chunk': 'bad'}), isNull);
      expect(
        service.collectChunk({'chunk': 'bad', 'i': 5, 'n': 2, 'd': 'x'}),
        isNull,
      );
      expect(
        service.collectChunk({'chunk': 'bad', 'i': -1, 'n': 2, 'd': 'x'}),
        isNull,
      );
    });
  });
}
