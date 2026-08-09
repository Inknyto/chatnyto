import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/crypto_service.dart';
import 'adb_client.dart';

/// What kind of thing is on the other end.
enum AdbTargetKind {
  /// Something running adbd itself: a television, a phone with wireless
  /// debugging on, an emulator. Authenticated with this app's own key.
  device,

  /// A computer running the adb server. No authentication, an entirely
  /// different protocol, and any number of devices behind it.
  computer,
}

/// One saved adb connection.
class AdbTarget {
  AdbTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.kind,
  });

  final String id;
  String name;
  String host;
  int port;
  AdbTargetKind kind;

  String get address => '$host:$port';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'kind': kind.name,
      };

  static AdbTarget? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return AdbTarget(
      id: id,
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 5555,
      // An unknown kind from a newer build reads as a plain device rather
      // than making the whole list unreadable.
      kind: AdbTargetKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => AdbTargetKind.device,
      ),
    );
  }

  /// The port to offer for a kind, when the user has not said.
  static int defaultPort(AdbTargetKind kind) =>
      kind == AdbTargetKind.computer ? 5037 : 5555;
}

/// The saved list of things this phone can debug, and the live connections
/// to them.
///
/// Saved per account, like everything else: which machines somebody debugs
/// is as much their business as who they talk to.
class AdbTargets extends ChangeNotifier {
  AdbTargets._();

  static final AdbTargets instance = AdbTargets._();

  final List<AdbTarget> _targets = [];
  final Map<String, AdbClient> _connections = {};
  final Map<String, String> _status = {};
  bool _loaded = false;

  List<AdbTarget> get targets => List.unmodifiable(_targets);

  String get _key => 'adb.targets.v1${IdentityService.instance.scope}';

  /// What last happened with a target, for the line under its name.
  String statusOf(String id) => _status[id] ?? '';

  bool isConnected(String id) => _connections[id]?.isOpen ?? false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _targets
      ..clear()
      ..addAll((prefs.getStringList(_key) ?? [])
          .map((s) => AdbTarget.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .whereType<AdbTarget>());
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, _targets.map((t) => jsonEncode(t.toJson())).toList());
  }

  Future<void> save(AdbTarget target) async {
    final at = _targets.indexWhere((t) => t.id == target.id);
    if (at >= 0) {
      _targets[at] = target;
    } else {
      _targets.add(target);
    }
    await _save();
    notifyListeners();
  }

  Future<void> remove(AdbTarget target) async {
    _targets.removeWhere((t) => t.id == target.id);
    await disconnect(target);
    _status.remove(target.id);
    await _save();
    notifyListeners();
  }

  /// Opens a connection to a device, or checks that a computer's adb server
  /// answers. Returns what to tell the user.
  Future<String> connect(AdbTarget target) async {
    if (target.kind == AdbTargetKind.computer) {
      final devices = await AdbHost(target.host, port: target.port).devices();
      final message = devices.isEmpty
          ? 'The adb server answered, but has no devices attached.'
          : '${devices.length} device${devices.length == 1 ? '' : 's'} '
              'attached';
      _status[target.id] = message;
      notifyListeners();
      return message;
    }

    await disconnect(target);
    final (result, client) =
        await AdbClient.connect(target.host, port: target.port);
    if (client != null) {
      _connections[target.id] = client;
      _status[target.id] = client.banner.isEmpty ? 'Connected' : client.banner;
    } else {
      _status[target.id] = result.detail.isEmpty
          ? switch (result.status) {
              AdbStatus.awaitingApproval => 'Waiting for approval',
              AdbStatus.unreachable => 'No answer',
              AdbStatus.refused => 'Refused',
              AdbStatus.connected => 'Connected',
            }
          : result.detail;
    }
    notifyListeners();
    return _status[target.id]!;
  }

  Future<void> disconnect(AdbTarget target) async {
    final client = _connections.remove(target.id);
    await client?.close();
    notifyListeners();
  }

  /// Runs a command against a device target, connecting first if needed.
  Future<String> shell(AdbTarget target, String command) async {
    if (target.kind == AdbTargetKind.computer) {
      return 'Choose a device behind this computer first.';
    }
    var client = _connections[target.id];
    if (client == null || !client.isOpen) {
      await connect(target);
      client = _connections[target.id];
    }
    if (client == null) return statusOf(target.id);
    return client.shell(command);
  }

  /// Drops everything when the account changes.
  Future<void> reset() async {
    for (final client in _connections.values) {
      await client.close();
    }
    _connections.clear();
    _targets.clear();
    _status.clear();
    _loaded = false;
    notifyListeners();
  }

  static String newId() =>
      'adb-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
