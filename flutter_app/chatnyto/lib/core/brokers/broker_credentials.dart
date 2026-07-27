import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A broker's sign-in, kept out of the app's own storage and out of the UI.
///
/// Broker credentials used to be written into shared preferences alongside
/// the address and shown back in the edit dialog. Both are wrong: shared
/// preferences is a plain file that any backup picks up, and a password
/// re-displayed in a text field is a password anybody holding the phone can
/// read. They now live in the platform keystore (Android Keystore, iOS
/// Keychain, libsecret, DPAPI) and are only ever read by the connection
/// code — never by a widget.
class BrokerCredentials {
  BrokerCredentials._();

  static final BrokerCredentials instance = BrokerCredentials._();

  static const _prefix = 'broker.credentials.';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _key(String brokerName) => '$_prefix$brokerName';

  /// Stores (or clears, when both are empty) the sign-in for [brokerName].
  Future<void> save(String brokerName,
      {required String username, required String password}) async {
    if (username.isEmpty && password.isEmpty) {
      await forget(brokerName);
      return;
    }
    try {
      await _storage.write(
        key: _key(brokerName),
        value: jsonEncode({'u': username, 'p': password}),
      );
    } catch (error) {
      debugPrint('Could not store the broker sign-in: $error');
    }
  }

  /// The stored sign-in, or a pair of empty strings for an open broker.
  Future<({String username, String password})> read(String brokerName) async {
    try {
      final raw = await _storage.read(key: _key(brokerName));
      if (raw == null) return (username: '', password: '');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        username: json['u'] as String? ?? '',
        password: json['p'] as String? ?? '',
      );
    } catch (error) {
      debugPrint('Could not read the broker sign-in: $error');
      return (username: '', password: '');
    }
  }

  /// Whether a sign-in is on file — the only thing the UI is allowed to
  /// know, so it can say "saved" instead of showing the password.
  Future<bool> has(String brokerName) async {
    final stored = await read(brokerName);
    return stored.username.isNotEmpty || stored.password.isNotEmpty;
  }

  Future<void> forget(String brokerName) async {
    try {
      await _storage.delete(key: _key(brokerName));
    } catch (error) {
      debugPrint('Could not remove the broker sign-in: $error');
    }
  }

  /// Follows a broker that was renamed, so its sign-in is not orphaned.
  Future<void> rename(String from, String to) async {
    if (from == to) return;
    final stored = await read(from);
    if (stored.username.isEmpty && stored.password.isEmpty) return;
    await save(to, username: stored.username, password: stored.password);
    await forget(from);
  }
}
