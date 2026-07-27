import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// What a network published about itself.
class NetworkProfile {
  NetworkProfile({
    required this.name,
    required this.url,
    this.port = 0,
    this.username = '',
    this.password = '',
  });

  /// Human name for the network, shown in the broker list.
  final String name;

  /// Full connection URL — `wss://…/mqtt`, `mqtts://…`, `mqtt://…`.
  final String url;

  /// 0 when the URL's scheme default applies.
  final int port;

  final String username;
  final String password;

  bool get needsSignIn => username.isNotEmpty || password.isNotEmpty;
}

/// Turns the address of a running ChatNyto server into everything needed to
/// connect to its broker.
///
/// The user should only ever have to type the address they already know —
/// `supa-tech.com` — and never a broker port, a WebSocket path or, above
/// all, a password. A server answers for itself at
/// `https://<host>/.well-known/chatnyto.json`:
///
/// ```json
/// {
///   "name": "Supa Tech",
///   "url": "wss://supa-tech.com/mqtt",
///   "username": "chatnyto",
///   "password": "…"
/// }
/// ```
///
/// The document is fetched over HTTPS, so the credential it carries is only
/// ever seen by the app; it goes straight into the keystore and is never
/// displayed. When a host publishes no such document the address is used
/// as typed, which is what a bare LAN or LoRa broker needs.
class NetworkDirectory {
  NetworkDirectory._();

  static final NetworkDirectory instance = NetworkDirectory._();

  static const wellKnownPath = '/.well-known/chatnyto.json';
  static const _timeout = Duration(seconds: 6);

  /// Looks [address] up. Returns null when the host publishes nothing, which
  /// is not an error — it just means "connect to it as typed".
  Future<NetworkProfile?> lookup(String address) async {
    final host = _hostOf(address);
    if (host.isEmpty) return null;
    try {
      final response = await http
          .get(Uri.parse('https://$host$wellKnownPath'))
          .timeout(_timeout);
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final url = json['url'] as String?;
      if (url == null || url.isEmpty) return null;
      return NetworkProfile(
        name: json['name'] as String? ?? host,
        url: url,
        port: (json['port'] as num?)?.toInt() ?? 0,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
      );
    } catch (error) {
      // Offline, no such host, self-signed certificate, plain LAN broker:
      // all of these simply mean there is no profile to use.
      debugPrint('No network profile at $host: $error');
      return null;
    }
  }

  /// The bare hostname of whatever the user typed: `supa-tech.com`,
  /// `https://supa-tech.com/`, `wss://supa-tech.com/mqtt` and
  /// `supa-tech.com:8883` all give `supa-tech.com`. An IP address returns
  /// empty — a LAN broker has no certificate to fetch a profile over.
  String _hostOf(String address) {
    var raw = address.trim();
    if (raw.isEmpty) return '';
    if (!raw.contains('://')) raw = 'https://$raw';
    final host = Uri.tryParse(raw)?.host ?? '';
    if (host.isEmpty || !host.contains('.')) return '';
    // Numeric addresses are local brokers, not published servers.
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) return '';
    return host;
  }
}
