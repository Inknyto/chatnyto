import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_client.dart';

/// Keeps ChatNyto receiving messages while it is not the app in front.
///
/// Android will freeze or kill a backgrounded process, and with it the MQTT
/// connections. A foreground service — the persistent "ChatNyto is
/// connected" notification — keeps the process (and therefore the existing
/// broker connections and their heartbeat, which live in the main isolate)
/// running, and makes it start again after a reboot.
///
/// While the app's process lives, that is all the service has to do: the
/// app's own code keeps the connections and everything arrives as usual.
/// Once the app is closed and the process is taken away, the service comes
/// back in an isolate of its own where none of that state exists — so it
/// becomes a small client itself, just enough to make the phone ring. See
/// [BackgroundClient] for where that line is drawn and why.
@pragma('vm:entry-point')
void startBackgroundService() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // A fresh isolate has no plugins registered until this is called, and
    // without them there is no secure storage, so no keys, so nothing
    // readable on any topic.
    DartPluginRegistrant.ensureInitialized();
    await BackgroundClient.instance.tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    BackgroundClient.instance.tick();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  /// Tapping the ring opens the app, which is the whole point of it.
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}

class BackgroundService {
  BackgroundService._();

  static final BackgroundService instance = BackgroundService._();

  static const _prefKey = 'background.stayConnected';

  bool get _supported => Platform.isAndroid || Platform.isIOS;

  /// Whether the user wants ChatNyto to stay connected in the background.
  /// On by default — an offline-first messenger that stops receiving the
  /// moment you switch apps is not much of a messenger.
  Future<bool> enabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  void configure() {
    if (!_supported) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'chatnyto_background',
        channelName: 'Staying connected',
        channelDescription:
            'Keeps ChatNyto connected to your networks so messages arrive.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Fifteen seconds, because this tick is what decides whether the app
        // is still alive and whether the service has to take over listening.
        // A minute of that decision being wrong is a minute of missed calls.
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the service if the user wants it. Safe to call repeatedly, and
  /// worth calling again whenever the app comes back to the front: the
  /// service is the thing that keeps the process alive, so if the system
  /// took it away, that is exactly the moment to put it back.
  Future<void> startIfEnabled() async {
    if (!_supported || !await enabled()) return;
    await start();
  }

  /// Whether the process is currently being held open.
  Future<bool> running() async {
    if (!_supported) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (!_supported) return;
    try {
      configure();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        notificationTitle: 'ChatNyto is connected',
        notificationText: 'Messages and calls arrive while the app is closed.',
        callback: startBackgroundService,
      );
    } catch (error) {
      // A refused permission or an OEM restriction must not break the app.
      debugPrint('Could not start the background service: $error');
    }
  }

  /// Whether Android has agreed to leave this app alone.
  ///
  /// A foreground service is supposed to keep the process alive, and on
  /// stock Android it does. Manufacturers layer their own battery saving on
  /// top of it, and that layer will kill a backgrounded app regardless —
  /// which is why a messenger can look as though it "forgot" its networks
  /// after being closed for a while. Being on the exemption list is what
  /// actually settles it.
  Future<bool> unrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return true;
    }
  }

  /// Asks for that exemption. The system shows the prompt; if the phone
  /// refuses to show one, the settings page is opened instead so there is
  /// always a way through.
  Future<bool> requestUnrestricted() async {
    if (!Platform.isAndroid) return true;
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return true;
      }
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        return true;
      }
      await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings();
      return FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (error) {
      debugPrint('Could not ask for the battery exemption: $error');
      return false;
    }
  }

  Future<void> stop() async {
    if (!_supported) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (error) {
      debugPrint('Could not stop the background service: $error');
    }
  }
}
