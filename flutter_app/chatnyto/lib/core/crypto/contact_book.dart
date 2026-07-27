import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto_service.dart';

/// People this device knows, whether or not they are on the air.
///
/// Presence announcements only tell you about whoever happens to be
/// connected right now. A contact someone handed over by QR code or link
/// has to survive that: you should be able to write to them the moment they
/// come back, without waiting to see them first.
///
/// Contacts are keyed by X25519 public key, so the same person added twice —
/// scanned in the street and then heard on a network — is one entry. That
/// key is the person; a display name is only a label they chose.
class ContactBook extends ChangeNotifier {
  ContactBook._();

  static final ContactBook instance = ContactBook._();

  static const _prefKey = 'contacts.v1';

  final Map<String, PublicIdentity> _contacts = {};
  bool _loaded = false;

  List<PublicIdentity> get contacts {
    final list = _contacts.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  String get _key => 'contacts.v1${IdentityService.instance.scope}';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    // Falls back to the unscoped key so contacts saved before accounts
    // existed are not lost.
    final stored =
        prefs.getStringList(_key) ?? prefs.getStringList(_prefKey) ?? [];
    for (final entry in stored) {
      try {
        final identity =
            PublicIdentity.fromJson(jsonDecode(entry) as Map<String, dynamic>);
        if (identity != null) _contacts[identity.x25519PublicKey] = identity;
      } catch (_) {
        // Skip anything that no longer parses.
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      _contacts.values.map((c) => jsonEncode(c.toJson())).toList(),
    );
  }

  /// Adds or refreshes a contact. Returns false when the advertisement does
  /// not verify against its own key — an unsigned contact is worthless,
  /// since the whole point of storing it is to be able to trust it later.
  Future<bool> add(PublicIdentity identity) async {
    await load();
    if (!await identity.verify()) return false;
    _contacts[identity.x25519PublicKey] = identity;
    await _save();
    notifyListeners();
    return true;
  }

  Future<void> remove(String x25519PublicKey) async {
    await load();
    _contacts.remove(x25519PublicKey);
    await _save();
    notifyListeners();
  }

  bool knows(String x25519PublicKey) =>
      _contacts.containsKey(x25519PublicKey);

  /// Everyone worth showing in a people list: saved contacts and whoever is
  /// currently announcing themselves, each appearing once.
  ///
  /// A live announcement wins over the stored copy — it carries the name and
  /// picture the person is using now. [exclude] drops yourself from the list.
  List<PublicIdentity> merged(List<PublicIdentity> live,
      {String exclude = ''}) {
    final byKey = <String, PublicIdentity>{};
    for (final contact in _contacts.values) {
      byKey[contact.x25519PublicKey] = contact;
    }
    for (final peer in live) {
      byKey[peer.x25519PublicKey] = peer;
    }
    byKey.remove(exclude);
    final list = byKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }
}
