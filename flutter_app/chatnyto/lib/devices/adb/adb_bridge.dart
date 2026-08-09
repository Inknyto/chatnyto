import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ways of running adb that are not this app's own TCP client.
///
/// [AdbClient] reaches anything with adbd listening on a port, which covers
/// televisions, other phones with wireless debugging on, and emulators. Two
/// things it cannot do, both on this phone:
///
///  * **Talk to devices on this phone's USB port.** That needs the USB host
///    stack and a driver, which an app cannot have. Termux can, because it
///    ships a real adb binary with libusb underneath it.
///  * **Reach this phone's own adbd.** A phone's wireless debugging has to
///    be paired before it will talk, and pairing needs a code the user reads
///    off their own settings screen. Shizuku is the way round that: it is a
///    service the user has already started with adb or root, and it will run
///    commands with shell privileges for any app it has granted permission
///    to — which is exactly what `adb shell` is, without the adb.
///
/// Both are optional. Nothing here is required for the app to control a
/// television, and every method answers with a reason rather than throwing
/// when the other app is not installed.
class AdbBridge {
  AdbBridge._();

  static final AdbBridge instance = AdbBridge._();

  static const _channel = MethodChannel('chatnyto/adb_bridge');

  bool get supported => Platform.isAndroid;

  /// Whether Shizuku is installed and running.
  ///
  /// Running matters as much as installed: Shizuku loses its privileges on
  /// every reboot until the user starts it again, and an app that reports
  /// "available" for an installed-but-stopped Shizuku sends the user looking
  /// for a fault in the wrong place.
  Future<ShizukuState> shizukuState() async {
    if (!supported) return ShizukuState.unsupported;
    try {
      final state = await _channel.invokeMethod<String>('shizukuState');
      return ShizukuState.values.firstWhere(
        (s) => s.name == state,
        orElse: () => ShizukuState.missing,
      );
    } on PlatformException catch (error) {
      debugPrint('[adb] shizuku: ${error.message}');
      return ShizukuState.missing;
    } on MissingPluginException {
      return ShizukuState.unsupported;
    }
  }

  /// Asks Shizuku for permission. The user answers in a dialog Shizuku puts
  /// up, so this returns as soon as they have.
  Future<bool> requestShizuku() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('shizukuRequest') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Runs a shell command with Shizuku's privileges — that is, with the
  /// same authority `adb shell` has on this phone.
  Future<String> shizukuRun(String command) async {
    if (!supported) return 'Only on Android.';
    try {
      return await _channel.invokeMethod<String>(
              'shizukuRun', {'command': command}) ??
          '';
    } on PlatformException catch (error) {
      return error.message ?? 'Shizuku refused that.';
    } on MissingPluginException {
      return 'This build has no Shizuku support.';
    }
  }

  /// Whether Termux is installed and has granted us permission to run
  /// commands in it.
  Future<bool> termuxAvailable() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('termuxAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Runs Termux's own adb.
  ///
  /// This is the path to a USB-attached device: `adb devices`, `adb -s …
  /// shell …`, and everything else the real binary can do, including talking
  /// to hardware plugged into this phone's socket.
  ///
  /// Termux has to have been given the RUN_COMMAND permission, and
  /// `allow-external-apps=true` set in its properties — both deliberate acts
  /// by whoever owns the phone, and neither of which this app can do for
  /// them. The reply says which one is missing.
  Future<String> termuxAdb(List<String> arguments) async {
    if (!supported) return 'Only on Android.';
    try {
      return await _channel.invokeMethod<String>('termuxRun', {
            'path': '/data/data/com.termux/files/usr/bin/adb',
            'arguments': arguments,
          }) ??
          '';
    } on PlatformException catch (error) {
      return error.message ?? 'Termux would not run that.';
    } on MissingPluginException {
      return 'This build has no Termux support.';
    }
  }
}

/// Where Shizuku stands on this phone.
enum ShizukuState {
  /// Installed, running, and it has said yes to us.
  granted,

  /// Running, but it has not been asked yet or the user said no.
  denied,

  /// Installed but not started. Shizuku has to be started after every
  /// reboot, from its own app.
  notRunning,

  /// Not installed.
  missing,

  /// Not Android.
  unsupported,
}

extension ShizukuStateLabel on ShizukuState {
  String get label => switch (this) {
        ShizukuState.granted => 'Ready',
        ShizukuState.denied => 'Permission not granted',
        ShizukuState.notRunning => 'Installed, but not started',
        ShizukuState.missing => 'Not installed',
        ShizukuState.unsupported => 'Not available on this platform',
      };

  String get hint => switch (this) {
        ShizukuState.granted =>
          'Commands run with the same authority adb shell has.',
        ShizukuState.denied => 'Tap to ask Shizuku for permission.',
        ShizukuState.notRunning =>
          'Open Shizuku and start it. It has to be started again after '
              'every reboot.',
        ShizukuState.missing =>
          'Shizuku lets an app run shell commands without a computer '
              'attached. Without it, this phone cannot debug itself.',
        ShizukuState.unsupported => '',
      };
}
