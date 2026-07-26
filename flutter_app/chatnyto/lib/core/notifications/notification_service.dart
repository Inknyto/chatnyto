import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System notifications for messages that arrive while the app is in the
/// background or while another chat is open.
///
/// Everything is best-effort: on platforms without a notification backend
/// (or when the user denied the permission) the calls simply do nothing, so
/// the messaging path never fails because of a notification.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'notifications';
  static const _soundKey = 'notifications.sound';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _available = false;
  int _nextId = 1;

  /// Chat currently on screen — no notification is raised for it while the
  /// app is actually in front of the user.
  String? activeChatId;

  /// Whether the app is in the foreground. Once it is backgrounded every
  /// message notifies, including the chat that was left open.
  bool appInForeground = true;

  bool get _supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS ||
      Platform.isLinux;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    if (!_supported) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        ),
      );
      _available = true;
      await requestPermission();
    } catch (error) {
      debugPrint('Notifications unavailable: $error');
      _available = false;
    }
  }

  /// Asks for the runtime permission (Android 13+, iOS, macOS).
  Future<void> requestPermission() async {
    if (!_available) return;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      } else if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  Future<bool> get _enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<NotificationSound> sound() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_soundKey);
    return NotificationSound.values.firstWhere(
      (s) => s.name == stored,
      orElse: () => NotificationSound.chime,
    );
  }

  Future<void> setSound(NotificationSound sound) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soundKey, sound.name);
    // Android channels are immutable once created, so each sound lives in
    // its own channel and switching means publishing to a different one.
    // Play it right away so the choice can be heard.
    await _preview(sound);
  }

  Future<void> _preview(NotificationSound sound) async {
    await init();
    if (!_available) return;
    try {
      await _plugin.show(
        0,
        'ChatNyto',
        'This is how new messages will sound.',
        _detailsFor(sound),
      );
    } catch (error) {
      debugPrint('Could not preview the notification sound: $error');
    }
  }

  NotificationDetails _detailsFor(NotificationSound sound) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        sound.channelId,
        sound.channelName,
        channelDescription: 'New chat messages',
        importance: Importance.high,
        priority: Priority.high,
        playSound: sound != NotificationSound.silent,
        sound: sound == NotificationSound.chime
            ? const RawResourceAndroidNotificationSound('chatnyto_chime')
            : null,
      ),
      iOS: DarwinNotificationDetails(
        presentSound: sound != NotificationSound.silent,
      ),
      macOS: DarwinNotificationDetails(
        presentSound: sound != NotificationSound.silent,
      ),
      linux: const LinuxNotificationDetails(),
    );
  }

  /// Raises a "new message" notification unless the chat is already open or
  /// the user turned notifications off in the settings.
  Future<void> showMessage({
    required String chatId,
    required String chatTitle,
    required String sender,
    required String preview,
  }) async {
    if (appInForeground && chatId == activeChatId) return;
    await init();
    if (!_available || !await _enabled) return;
    final body = sender.isEmpty || sender == chatTitle
        ? preview
        : '$sender: $preview';
    try {
      await _plugin.show(
        _nextId++,
        chatTitle,
        body,
        _detailsFor(await sound()),
        payload: chatId,
      );
    } catch (error) {
      debugPrint('Could not show notification: $error');
    }
  }
}

/// The alert tone used for new messages. Each entry maps to its own Android
/// notification channel, because a channel's sound cannot be changed after
/// it has been created.
enum NotificationSound {
  chime('ChatNyto chime', 'chatnyto_messages_chime', 'Messages (chime)'),
  system('Your default tone', 'chatnyto_messages', 'Messages'),
  silent('Silent', 'chatnyto_messages_silent', 'Messages (silent)');

  const NotificationSound(this.label, this.channelId, this.channelName);

  final String label;
  final String channelId;
  final String channelName;
}
