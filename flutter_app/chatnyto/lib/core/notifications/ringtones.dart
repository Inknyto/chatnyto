import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The sounds the user chose, from their own files.
///
/// A ringtone is one of the few things about a phone that is genuinely
/// personal, and "one of our three" is a poor answer. Any audio file on the
/// device can be used instead.
///
/// The file is copied into the app's own storage rather than referred to
/// where it sits. The picker hands back a permission to read one file, once;
/// that permission does not survive a restart, and a ringtone that stops
/// working next week would be worse than not offering the choice. A copy is
/// a few hundred kilobytes and it always plays.
///
/// Playback is the app's own rather than the notification channel's, because
/// Android fixes a channel's sound when the channel is created and cannot
/// read a file that belongs to this app. So when a tone has been chosen, the
/// notification is published silently and the sound comes from here.
class Ringtones extends ChangeNotifier {
  Ringtones._();

  static final Ringtones instance = Ringtones._();

  static const _callKey = 'ringtone.call';
  static const _messageKey = 'ringtone.message';

  final AudioPlayer _ringer = AudioPlayer();
  final AudioPlayer _alert = AudioPlayer();

  String? _call;
  String? _message;
  bool _loaded = false;
  bool _ringing = false;

  /// The chosen file for incoming calls, or null for the system's own.
  String? get callTone => _call;
  String? get messageTone => _message;

  bool get hasCallTone => _call != null;
  bool get hasMessageTone => _message != null;

  /// Just the file name, for the settings row.
  static String labelFor(String? path) =>
      path == null ? 'Default' : path.split(Platform.pathSeparator).last;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _call = await _stillThere(prefs.getString(_callKey));
    _message = await _stillThere(prefs.getString(_messageKey));
    notifyListeners();
  }

  /// A tone the user deleted from outside the app is no tone at all.
  Future<String?> _stillThere(String? path) async {
    if (path == null) return null;
    return await File(path).exists() ? path : null;
  }

  // --------------------------------------------------------------- picking

  /// Asks for an audio file and keeps a copy. Returns the new tone's name,
  /// or null when nothing was chosen.
  Future<String?> pickCallTone() => _pick(_callKey, 'call');

  Future<String?> pickMessageTone() => _pick(_messageKey, 'message');

  Future<String?> _pick(String key, String slot) async {
    await load();
    try {
      const audio = XTypeGroup(
        label: 'Audio',
        // Both, because Android matches on MIME and the desktop pickers
        // match on the extension.
        mimeTypes: <String>['audio/*'],
        extensions: <String>['mp3', 'ogg', 'wav', 'm4a', 'aac', 'opus', 'flac'],
      );
      final file = await openFile(acceptedTypeGroups: const [audio]);
      if (file == null) return null;

      final directory = await getApplicationSupportDirectory();
      final tones = Directory('${directory.path}/ringtones');
      if (!await tones.exists()) await tones.create(recursive: true);
      // A fixed name per slot, so choosing a fifth ringtone does not leave
      // four forgotten copies behind.
      final extension = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'audio';
      final destination = File('${tones.path}/$slot.$extension');
      for (final old in tones.listSync()) {
        if (old is File &&
            old.uri.pathSegments.last.startsWith('$slot.') &&
            old.path != destination.path) {
          await old.delete();
        }
      }
      await destination.writeAsBytes(await file.readAsBytes());

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, destination.path);
      if (key == _callKey) {
        _call = destination.path;
      } else {
        _message = destination.path;
      }
      notifyListeners();
      return file.name;
    } catch (error) {
      debugPrint('Could not set the ringtone: $error');
      return null;
    }
  }

  Future<void> clearCallTone() => _clear(_callKey);

  Future<void> clearMessageTone() => _clear(_messageKey);

  Future<void> _clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(key);
    await prefs.remove(key);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // Already gone.
      }
    }
    if (key == _callKey) {
      _call = null;
    } else {
      _message = null;
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- playing

  /// Rings until [stopRinging]. Does nothing when no tone was chosen — the
  /// notification channel handles that case on its own.
  Future<void> startRinging() async {
    await load();
    final path = _call;
    if (path == null || _ringing) return;
    _ringing = true;
    try {
      await _ringer.setReleaseMode(ReleaseMode.loop);
      await _ringer.setVolume(1);
      await _ringer.play(DeviceFileSource(path));
    } catch (error) {
      debugPrint('Could not ring with $path: $error');
      _ringing = false;
    }
  }

  Future<void> stopRinging() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _ringer.stop();
    } catch (error) {
      debugPrint('Could not stop ringing: $error');
    }
  }

  /// One-shot alert for a new message.
  Future<void> playMessageTone() async {
    await load();
    final path = _message;
    if (path == null) return;
    try {
      await _alert.setReleaseMode(ReleaseMode.stop);
      await _alert.play(DeviceFileSource(path));
    } catch (error) {
      debugPrint('Could not play the message tone: $error');
    }
  }

  /// Plays a chosen tone once so it can be heard while choosing it.
  Future<void> preview(String? path) async {
    if (path == null) return;
    try {
      await _alert.setReleaseMode(ReleaseMode.stop);
      await _alert.play(DeviceFileSource(path));
    } catch (error) {
      debugPrint('Could not preview $path: $error');
    }
  }
}
