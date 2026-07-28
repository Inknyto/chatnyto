import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
// Both packages name an `IosAudioCategory`, and they mean different things.
import 'package:record/record.dart' hide IosAudioCategory;

/// Voice carried over MQTT, for the calls WebRTC cannot make.
///
/// A direct peer-to-peer stream is always better — it is lower latency and
/// the platform's own echo canceller and jitter buffer come with it — but it
/// needs a route between the two devices, and there are three common cases
/// where none exists: both phones on mobile data behind carrier NAT, a WiFi
/// network with client isolation, and two devices that share only a broker
/// (the LoRa box, or a server) and nothing else. In all three the broker is
/// provably reachable from both ends — the ring got through, after all — so
/// the audio takes the same road as the messages.
///
/// The stream is deliberately small: 8 kHz mono, IMA ADPCM at 4 bits per
/// sample, in 60 ms frames. That is 4 kB/s of audio, about 8 kB/s once each
/// frame is encrypted and base64'd into its envelope — telephone quality,
/// and little enough to survive a phone's mobile data allowance and a
/// modest broker. Frames carry their own predictor state, so one that goes
/// missing costs 60 ms rather than corrupting everything after it.
///
/// Echo is the reason capture asks for the voice-communication source and
/// puts the device in communication mode: that is what hands us the
/// hardware echo canceller WebRTC would otherwise have provided.
class VoiceRelay {
  VoiceRelay._();

  static final VoiceRelay instance = VoiceRelay._();

  static const sampleRate = 8000;

  /// 60 ms of audio. Long enough that per-frame overhead stays small,
  /// short enough not to be heard as delay.
  static const frameSamples = 480;

  final AudioRecorder _recorder = AudioRecorder();
  final AdpcmEncoder _encoder = AdpcmEncoder();
  final AdpcmDecoder _decoder = AdpcmDecoder();

  StreamSubscription<Uint8List>? _capture;
  final BytesBuilder _pending = BytesBuilder();
  bool _running = false;
  bool _muted = false;
  bool _playing = false;

  /// Set while a frame is being handed out, so the caller publishes it.
  void Function(Uint8List frame)? onFrame;

  bool get running => _running;

  /// Relaying needs raw capture and raw playback, which exist on the phones
  /// this matters for. On a desktop the direct path is the only one.
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  set muted(bool value) => _muted = value;

  /// Starts capturing and playing. Returns false when the platform cannot
  /// do it, or the microphone was refused — the caller then keeps whatever
  /// WebRTC managed on its own.
  Future<bool> start() async {
    if (_running) return true;
    if (!supported) return false;
    try {
      if (!await _recorder.hasPermission()) return false;

      await FlutterPcmSound.setup(
        sampleRate: sampleRate,
        channelCount: 1,
        iosAudioCategory: IosAudioCategory.playAndRecord,
      );
      // Topped up with silence when nothing has arrived, so the player keeps
      // running instead of stopping and clicking on the next frame.
      FlutterPcmSound.setFeedThreshold(sampleRate ~/ 10);
      FlutterPcmSound.setFeedCallback(_onStarved);
      _playing = true;

      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
        androidConfig: AndroidRecordConfig(
          // The pair that gets us the platform's echo canceller. Without
          // them a speakerphone call feeds itself back to the other end.
          audioSource: AndroidAudioSource.voiceCommunication,
          audioManagerMode: AudioManagerMode.modeInCommunication,
        ),
      ));
      _capture = stream.listen(_onCaptured, onError: (Object error) {
        debugPrint('[relay] capture failed: $error');
      });
      _running = true;
      FlutterPcmSound.start();
      debugPrint('[relay] started');
      return true;
    } catch (error) {
      debugPrint('[relay] could not start: $error');
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    await _capture?.cancel();
    _capture = null;
    _pending.clear();
    try {
      await _recorder.cancel();
    } catch (_) {
      // Already stopped, or never started.
    }
    if (_playing) {
      _playing = false;
      FlutterPcmSound.setFeedCallback(null);
      try {
        await FlutterPcmSound.release();
      } catch (_) {
        // Nothing to release.
      }
    }
    _encoder.reset();
    _decoder.reset();
  }

  /// Capture arrives in whatever block size the platform likes; frames go
  /// out at a fixed size, so the tail of a block waits for the next one.
  void _onCaptured(Uint8List chunk) {
    if (!_running) return;
    _pending.add(chunk);
    const frameBytes = frameSamples * 2;
    if (_pending.length < frameBytes) return;

    final buffered = _pending.takeBytes();
    var offset = 0;
    while (buffered.length - offset >= frameBytes) {
      final view = Int16List.view(buffered.buffer, offset, frameSamples);
      // Muting happens here rather than by stopping the recorder: the far
      // end should hear silence, not a call that went dead.
      onFrame?.call(_encoder.encode(view, silent: _muted));
      offset += frameBytes;
    }
    if (offset < buffered.length) {
      _pending.add(Uint8List.sublistView(buffered, offset));
    }
  }

  /// Hands a frame that arrived from the other device to the speaker.
  void playFrame(Uint8List frame) {
    if (!_running || !_playing) return;
    try {
      FlutterPcmSound.feed(PcmArrayInt16(bytes: _decoder.decode(frame)));
    } catch (error) {
      debugPrint('[relay] could not play a frame: $error');
    }
  }

  void _onStarved(int remaining) {
    if (!_playing) return;
    try {
      FlutterPcmSound.feed(PcmArrayInt16.zeros(count: frameSamples));
    } catch (_) {
      // The player is going away.
    }
  }
}

// --------------------------------------------------------------- the codec

/// IMA ADPCM, the same 4-bit scheme WAV files have used for decades: one
/// nibble per sample, and a step size that walks up and down as the signal
/// does. Four times smaller than 16-bit PCM, no native library, and quick
/// enough that a decade-old phone encodes a frame in well under a
/// millisecond.
const List<int> _indexTable = [
  -1, -1, -1, -1, 2, 4, 6, 8, //
  -1, -1, -1, -1, 2, 4, 6, 8,
];

const List<int> _stepTable = [
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, //
  41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173,
  190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
  724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
  2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
  6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289,
  16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
];

/// Every frame starts with the predictor and step index it was encoded
/// from, so the decoder can pick up from any frame. A dropped frame costs
/// its own 60 ms and nothing more.
const _headerBytes = 3;

class AdpcmEncoder {
  int _predictor = 0;
  int _index = 0;

  void reset() {
    _predictor = 0;
    _index = 0;
  }

  Uint8List encode(Int16List samples, {bool silent = false}) {
    final out = Uint8List(_headerBytes + (samples.length + 1) ~/ 2);
    out[0] = _predictor & 0xff;
    out[1] = (_predictor >> 8) & 0xff;
    out[2] = _index;

    var byte = 0;
    for (var i = 0; i < samples.length; i++) {
      final code = _encodeSample(silent ? 0 : samples[i]);
      if (i.isEven) {
        byte = code;
      } else {
        out[_headerBytes + (i >> 1)] = (code << 4) | byte;
      }
    }
    if (samples.length.isOdd) {
      out[_headerBytes + (samples.length >> 1)] = byte;
    }
    return out;
  }

  int _encodeSample(int sample) {
    var step = _stepTable[_index];
    var diff = sample - _predictor;
    var code = 0;
    if (diff < 0) {
      code = 8;
      diff = -diff;
    }
    var delta = step >> 3;
    if (diff >= step) {
      code |= 4;
      diff -= step;
      delta += step;
    }
    step >>= 1;
    if (diff >= step) {
      code |= 2;
      diff -= step;
      delta += step;
    }
    step >>= 1;
    if (diff >= step) {
      code |= 1;
      delta += step;
    }
    _predictor = ((code & 8) != 0 ? _predictor - delta : _predictor + delta)
        .clamp(-32768, 32767);
    _index = (_index + _indexTable[code]).clamp(0, _stepTable.length - 1);
    return code;
  }
}

class AdpcmDecoder {
  int _predictor = 0;
  int _index = 0;

  void reset() {
    _predictor = 0;
    _index = 0;
  }

  ByteData decode(Uint8List frame) {
    if (frame.length <= _headerBytes) return ByteData(0);
    // Sign-extend: the predictor is a signed 16-bit sample.
    _predictor = (frame[0] | (frame[1] << 8)).toSigned(16);
    _index = frame[2].clamp(0, _stepTable.length - 1);

    final count = (frame.length - _headerBytes) * 2;
    final out = ByteData(count * 2);
    for (var i = 0; i < count; i++) {
      final packed = frame[_headerBytes + (i >> 1)];
      final code = i.isEven ? packed & 0x0f : (packed >> 4) & 0x0f;
      out.setInt16(i * 2, _decodeSample(code), Endian.host);
    }
    return out;
  }

  int _decodeSample(int code) {
    final step = _stepTable[_index];
    var delta = step >> 3;
    if ((code & 4) != 0) delta += step;
    if ((code & 2) != 0) delta += step >> 1;
    if ((code & 1) != 0) delta += step >> 2;
    _predictor = ((code & 8) != 0 ? _predictor - delta : _predictor + delta)
        .clamp(-32768, 32767);
    _index = (_index + _indexTable[code]).clamp(0, _stepTable.length - 1);
    return _predictor;
  }
}
