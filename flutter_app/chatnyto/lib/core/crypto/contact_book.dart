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
  static const _sharedPrefKey = 'contacts.shared';

  final Map<String, PublicIdentity> _contacts = {};

  /// Local names, keyed the same way. A person publishes the name they
  /// chose; this is the one you call them. Kept apart from the identity so
  /// it is never confused with something they signed — and never sent
  /// anywhere, because it is nobody else's business what you call them.
  final Map<String, String> _aliases = {};
  bool _loaded = false;
  bool _shared = false;

  List<PublicIdentity> get contacts {
    final list = _contacts.values.toList()
      ..sort((a, b) =>
          displayName(a).toLowerCase().compareTo(displayName(b).toLowerCase()));
    return list;
  }

  /// Whether every account on this device draws on the same address book.
  ///
  /// Off by default, and that default matters: keeping a work identity and a
  /// personal one apart is one of the reasons to have two, and it is no use
  /// if the people are shared. Some people do want one address book across
  /// both, though, so it is a choice rather than a rule.
  bool get shared => _shared;

  Future<void> setShared(bool value) async {
    if (_shared == value) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sharedPrefKey, value);
    _shared = value;
    // The set of contacts is a different set now.
    reset();
    await load();
  }

  /// Forgets what is held in memory, so the next account starts from its own
  /// storage. Without this, switching identity kept showing the previous
  /// account's contacts — they were merely hidden behind a different key,
  /// not actually reloaded.
  void reset() {
    _contacts.clear();
    _aliases.clear();
    _loaded = false;
    notifyListeners();
  }

  String get _key =>
      _shared ? _prefKey : 'contacts.v1${IdentityService.instance.scope}';

  String get _aliasKey => '$_key.alias';

  /// What to call someone: the name you gave them if you gave them one,
  /// otherwise the name they publish.
  String displayName(PublicIdentity person) {
    final alias = _aliases[person.x25519PublicKey];
    return alias == null || alias.isEmpty ? person.name : alias;
  }

  bool hasAlias(String x25519PublicKey) =>
      (_aliases[x25519PublicKey] ?? '').isNotEmpty;

  /// Renames a contact locally. An empty [name] goes back to theirs.
  Future<void> setAlias(String x25519PublicKey, String name) async {
    await load();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _aliases.remove(x25519PublicKey);
    } else {
      _aliases[x25519PublicKey] = trimmed;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aliasKey, jsonEncode(_aliases));
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    _shared = prefs.getBool(_sharedPrefKey) ?? false;
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
    try {
      final aliases = prefs.getString(_aliasKey);
      if (aliases != null) {
        (jsonDecode(aliases) as Map<String, dynamic>)
            .forEach((key, value) => _aliases[key] = value as String);
      }
    } catch (_) {
      // Names are a convenience; a corrupt map is not worth failing over.
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
      ..sort((a, b) =>
          displayName(a).toLowerCase().compareTo(displayName(b).toLowerCase()));
    return list;
  }
}
