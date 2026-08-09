import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/crypto/crypto_service.dart';
import 'device.dart';
import 'tv_remote.dart';

/// The devices the user has added, what they are doing, and how to tell them
/// to do something else.
///
/// Devices are stored per account, like everything else: the lamps in your
/// workshop are not the other account's business. The store is a plain list
/// under an account-scoped key — no encryption, because a device list is
/// addresses and topic names, and the thing worth protecting (the broker
/// sign-in that lets anyone publish to them) lives in the keystore already.
class DeviceService extends ChangeNotifier {
  DeviceService._();

  static final DeviceService instance = DeviceService._();

  /// Where a device's controls publish and listen. Anything under here is
  /// covered by the broker's ACL for authenticated users, and nothing else
  /// on the broker is.
  static const topicPrefix = 'chatnyto/devices';

  final List<Device> _devices = [];

  /// The last payload seen on each subscribed topic, which is what a reading
  /// shows and what tells a switch which way it is.
  final Map<String, String> _state = {};

  /// When each topic last said anything, so a device that has gone quiet can
  /// be shown as such rather than as whatever it last claimed.
  final Map<String, DateTime> _heardAt = {};

  bool _loaded = false;

  List<Device> get devices => List.unmodifiable(_devices);

  /// Devices grouped by room, in the order rooms were first used. Devices
  /// with no room come last, under the empty key.
  Map<String, List<Device>> get byRoom {
    final rooms = <String, List<Device>>{};
    for (final device in _devices.where((d) => d.room.isNotEmpty)) {
      rooms.putIfAbsent(device.room, () => []).add(device);
    }
    final loose = _devices.where((d) => d.room.isEmpty).toList();
    if (loose.isNotEmpty) rooms[''] = loose;
    return rooms;
  }

  /// The last thing heard on [topic], or null when nothing has been.
  String? stateOf(String topic) => _state[topic];

  /// Whether [topic] has said anything recently enough to be believed.
  bool isFresh(String topic, {Duration within = const Duration(minutes: 10)}) {
    final at = _heardAt[topic];
    return at != null && DateTime.now().difference(at) < within;
  }

  DateTime? heardAt(String topic) => _heardAt[topic];

  // ------------------------------------------------------------- storage

  Future<String> _key() async {
    if (!IdentityService.instance.isUnlocked) return 'devices.v1';
    final me = await IdentityService.instance.publicIdentity();
    return 'devices.v1.${me.fingerprint}';
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key());
      if (raw != null) {
        for (final entry in jsonDecode(raw) as List) {
          final device = Device.fromJson(Map<String, dynamic>.from(entry));
          if (device != null) _devices.add(device);
        }
      }
    } catch (error) {
      debugPrint('[devices] could not load: $error');
    }
    BrokerService.instance.onDeviceMessage = _onMessage;
    _watchTopics();
    notifyListeners();
  }

  /// Devices that publish outside the app's own tree are not covered by its
  /// wildcard, so the broker has to be told about each one by name.
  void _watchTopics() {
    final outside = topics.where((t) => !t.startsWith(topicPrefix));
    if (outside.isNotEmpty) BrokerService.instance.watchTopics(outside);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await _key(), Device.encode(_devices));
  }

  /// Drops everything held for the account being left.
  void reset() {
    _devices.clear();
    _state.clear();
    _heardAt.clear();
    _loaded = false;
    TvRemote.instance.releaseAll();
    notifyListeners();
  }

  // -------------------------------------------------------------- editing

  Future<void> add(Device device) async {
    _devices.add(device);
    await _save();
    _watchTopics();
    notifyListeners();
  }

  Future<void> update(Device device) async {
    final index = _devices.indexWhere((d) => d.id == device.id);
    if (index == -1) return;
    _devices[index] = device;
    await _save();
    _watchTopics();
    notifyListeners();
  }

  Future<void> remove(Device device) async {
    _devices.removeWhere((d) => d.id == device.id);
    await TvRemote.instance.release(device);
    await _save();
    notifyListeners();
  }

  /// A fresh id. The clock is enough: two devices are never added in the
  /// same millisecond by the same pair of hands.
  static String newId() =>
      'dev-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

  // ------------------------------------------------------------ operating

  /// Publishes [payload] on [control]'s topic.
  ///
  /// Returns false when there is no broker, which is the one failure worth
  /// telling the user about — everything else is the device's business and
  /// shows up as its state not changing.
  bool send(DeviceControl control, String payload) {
    if (!BrokerService.instance.anyConnected) return false;
    final topic = fullTopic(control.topic);
    // Retained, so a device that was unplugged comes back to the state it
    // was left in rather than to whatever its firmware defaults to.
    BrokerService.instance.publishToAll(topic, payload, retain: true);
    // Shown straight away rather than waiting for the echo. The broker sends
    // our own publications back, so the real state arrives a moment later
    // and overwrites this — but on a slow link a switch that does not move
    // when pressed reads as broken.
    _state[topic] = payload;
    _heardAt[topic] = DateTime.now();
    notifyListeners();
    return true;
  }

  /// Sends a key to a television and stores any token the pairing produced.
  Future<RemoteResult> pressKey(Device device, RemoteKey key) async {
    final (result, updated) = await TvRemote.instance.press(device, key);
    if (updated != null) await update(updated);
    return result;
  }

  /// Every topic the devices care about, so the broker knows to subscribe.
  List<String> get topics => [
        for (final device in _devices)
          for (final control in device.controls)
            if (control.topic.isNotEmpty) fullTopic(control.topic),
      ];

  /// A control's topic in full. A bare name is placed under the app's own
  /// device tree, which is what the broker's ACL allows; anything starting
  /// with a slash is taken as an absolute topic, for hardware that was
  /// already publishing somewhere before this app existed.
  static String fullTopic(String topic) {
    final clean = topic.trim();
    if (clean.startsWith('/')) return clean.substring(1);
    return '$topicPrefix/$clean';
  }

  void _onMessage(String topic, String payload) {
    _state[topic] = payload;
    _heardAt[topic] = DateTime.now();
    notifyListeners();
  }
}
