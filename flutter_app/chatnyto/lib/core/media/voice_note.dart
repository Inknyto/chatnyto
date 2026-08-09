import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
// Both this and flutter_pcm_sound (used by the relayed-call path) declare an
// `IosAudioCategory`, and they do not mean the same thing.
import 'package:record/record.dart' hide IosAudioCategory;

/// Recording and playing back voice notes.
///
/// A voice note is an ordinary chat message with an audio attachment, so it
/// travels the same end-to-end encrypted, chunked path as a photo and needs
/// nothing new from the broker. That is also why it is compressed hard:
/// AAC at 24 kbit/s mono is about 3 kB a second, so a minute is 180 kB and a
/// LoRa-sized link can still carry a short one.
///
/// This is a different thing from [VoiceRelay], which carries a live call.
/// A call needs frames out within milliseconds and tolerates losing some; a
/// voice note must arrive whole and does not care when.
class VoiceNotes {
  VoiceNotes._();

  static final VoiceNotes instance = VoiceNotes._();

  /// Where recording works. Elsewhere — Linux and Windows desktops, where
  /// the plugin has no capture backend — notes can still be played.
  static bool get canRecord => Platform.isAndroid || Platform.isIOS;

  /// Past this, a note is a podcast. The cap is enforced by the recorder
  /// rather than left to the user because the whole thing goes into one
  /// message, and an unbounded one would be split into thousands of pieces.
  static const maxDuration = Duration(minutes: 3);

  static const _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    sampleRate: 16000,
    numChannels: 1,
    bitRate: 24000,
    echoCancel: true,
    noiseSuppress: true,
    autoGain: true,
  );

  final AudioRecorder _recorder = AudioRecorder();
  String? _recordingPath;

  bool get isRecording => _recordingPath != null;

  /// Starts capturing. Returns false when there is no microphone permission
  /// or the platform cannot record, and leaves nothing behind either way.
  Future<bool> start() async {
    if (!canRecord || _recordingPath != null) return false;
    try {
      if (!await _recorder.hasPermission()) return false;
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/note-${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(_config, path: path);
      _recordingPath = path;
      return true;
    } catch (error) {
      debugPrint('Could not start recording: $error');
      _recordingPath = null;
      return false;
    }
  }

  /// How loud it is right now, 0..1, for the level meter. Silence and
  /// failure both read as zero, which is what the meter should show anyway.
  Future<double> level() async {
    if (_recordingPath == null) return 0;
    try {
      final amplitude = await _recorder.getAmplitude();
      // The plugin reports dBFS: 0 is clipping, -60 and below is silence.
      const floor = -45.0;
      final db = amplitude.current.clamp(floor, 0.0);
      return (db - floor) / -floor;
    } catch (_) {
      return 0;
    }
  }

  /// Stops and returns the recording, or null when nothing usable came out.
  /// The temporary file is removed either way — the bytes are what the
  /// caller wants, and leaving audio of the user on disk is not neutral.
  Future<Uint8List?> stop() async {
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null) return null;
    try {
      await _recorder.stop();
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes.isEmpty ? null : bytes;
    } catch (error) {
      debugPrint('Could not finish the recording: $error');
      return null;
    }
  }

  /// Throws the recording away.
  Future<void> cancel() async {
    final path = _recordingPath;
    _recordingPath = null;
    if (path == null) return;
    try {
      await _recorder.cancel();
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('Could not discard the recording: $error');
    }
  }

  /// Decodes the attachment of a received note, or null when there is none.
  static Uint8List? decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  /// Writes [bytes] somewhere a player can open, reusing the file when the
  /// same note is played again.
  ///
  /// Audio players want a URL or a path, not a buffer: handing them bytes
  /// makes them write a temporary file anyway, once per play. Keeping one
  /// file per note means replaying is instant and the cache is bounded by
  /// how many notes were opened, not by how often.
  static Future<String> cacheFile(Uint8List bytes, String id) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/voice-${fileSafe(id)}.m4a');
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  /// Makes [id] safe to put in a filename.
  ///
  /// A note is identified by its sender's fingerprint, which is written with
  /// colons — and Android's MediaPlayer refuses a path containing one
  /// outright, with nothing but MEDIA_ERROR_UNKNOWN to say why. Every note
  /// played silently and the bubble sprang back to the play button.
  static String fileSafe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
}

/// Plays one voice note at a time, everywhere in the app.
///
/// One player rather than one per bubble: starting a second note stops the
/// first, which is what a list of them should do, and a hundred idle
/// AudioPlayer instances in a long conversation is a hundred platform
/// objects doing nothing.
class VoiceNotePlayer extends ChangeNotifier {
  VoiceNotePlayer._() {
    _player.onPositionChanged.listen((position) {
      _position = position;
      notifyListeners();
    });
    _player.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) {
      _playing = null;
      _position = Duration.zero;
      notifyListeners();
    });
  }

  static final VoiceNotePlayer instance = VoiceNotePlayer._();

  final AudioPlayer _player = AudioPlayer();

  String? _playing;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Id of the note being played, or null when nothing is.
  String? get playing => _playing;
  Duration get position => _position;
  Duration get duration => _duration;

  bool isPlaying(String id) => _playing == id;

  /// Starts [id], or stops it when it is already the one playing.
  Future<void> toggle(String id, Uint8List bytes) async {
    if (_playing == id) {
      await stop();
      return;
    }
    try {
      final path = await VoiceNotes.cacheFile(bytes, id);
      await _player.stop();
      _playing = id;
      _position = Duration.zero;
      notifyListeners();
      await _player.play(DeviceFileSource(path));
    } catch (error) {
      debugPrint('Could not play the voice note: $error');
      _playing = null;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {
      // Already stopped.
    }
    _playing = null;
    _position = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration to) async {
    if (_playing == null) return;
    await _player.seek(to);
  }
}

/// "0:07" — the only duration format a voice note ever needs.
String voiceDurationLabel(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
