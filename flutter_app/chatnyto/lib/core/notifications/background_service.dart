import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps ChatNyto receiving messages while it is not the app in front.
///
/// Android will freeze or kill a backgrounded process, and with it the MQTT
/// connections. A foreground service — the persistent "ChatNyto is
/// connected" notification — keeps the process (and therefore the existing
/// broker connections and their heartbeat, which live in the main isolate)
/// running, and makes it start again after a reboot.
///
/// The service itself does no work: it exists to hold the process open. All
/// the messaging logic stays where the app's state already is.
@pragma('vm:entry-point')
void startBackgroundService() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
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
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Starts the service if the user wants it. Safe to call repeatedly.
  Future<void> startIfEnabled() async {
    if (!_supported || !await enabled()) return;
    await start();
  }

  Future<void> start() async {
    if (!_supported) return;
    try {
      configure();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.requestNotificationPermission();
      await FlutterForegroundTask.startService(
        notificationTitle: 'ChatNyto is connected',
        notificationText: 'Messages arrive even while the app is closed.',
        callback: startBackgroundService,
      );
    } catch (error) {
      // A refused permission or an OEM restriction must not break the app.
      debugPrint('Could not start the background service: $error');
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
