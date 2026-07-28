import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';

/// The helper servers a call may use to find a route between two devices.
///
/// On one network — the same WiFi, the LoRa box's access point — the two
/// devices see each other's addresses and need nothing. Over mobile data
/// they do not: each phone sits behind the carrier's NAT and knows only its
/// private address, so unless something tells it how it looks from outside,
/// it has no address to offer and the call can never connect. That is what
/// a STUN server does. When even that is not enough — two symmetric NATs,
/// or a WiFi network that forbids clients from talking to each other — a
/// TURN server forwards the audio.
///
/// A network can publish its own in its profile, next to the broker URL:
///
/// ```json
/// { "url": "wss://…/mqtt",
///   "ice": [{"urls": "turn:…:3478", "username": "…", "credential": "…"}] }
/// ```
///
/// Those are used first, because they belong to the server the user already
/// chose to trust. Public STUN is only added when the device is demonstrably
/// on the internet already — connected to a broker that is not a local
/// address — so an offline app still makes no outside connection of its own.
class IceDirectory {
  IceDirectory._();

  static final IceDirectory instance = IceDirectory._();

  static const _prefKey = 'calls.ice.v1';

  /// Used only when the app is already talking to a server on the internet
  /// and the network published nothing of its own.
  static const _publicStun = <Map<String, dynamic>>[
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.cloudflare.com:3478'},
  ];

  /// Records what a network published about itself. Servers are kept per
  /// network name so removing one network does not take another's TURN
  /// credentials with it.
  Future<void> remember(
      String network, List<Map<String, dynamic>> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _stored();
    if (servers.isEmpty) {
      all.remove(network);
    } else {
      all[network] = servers;
    }
    await prefs.setString(_prefKey, jsonEncode(all));
  }

  Future<void> forget(String network) => remember(network, const []);

  Future<Map<String, List<Map<String, dynamic>>>> _stored() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (network, servers) => MapEntry(
          network,
          (servers as List)
              .map((s) => Map<String, dynamic>.from(s as Map))
              .toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// The list handed to the peer connection when a call starts. Worked out
  /// afresh each time, because whether the device is on the internet is
  /// exactly the kind of thing that changes between one call and the next.
  Future<List<Map<String, dynamic>>> servers() async {
    final published = (await _stored()).values.expand((s) => s).toList();
    final list = <Map<String, dynamic>>[...published];
    if (BrokerService.instance.hasInternetNetwork) {
      final haveStun = published.any((server) =>
          (server['urls']?.toString() ?? '').startsWith('stun:'));
      if (!haveStun) list.addAll(_publicStun);
    }
    return list;
  }
}
