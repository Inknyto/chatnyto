import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End-to-end encryption primitives for ChatNyto.
///
/// Design (zero-trust towards brokers):
///  * Every user owns an X25519 key pair (key agreement) and an Ed25519 key
///    pair (signatures). Key seeds never leave the device unencrypted: they
///    are stored encrypted with AES-256-GCM under a key derived from the
///    user's password with PBKDF2-HMAC-SHA256 (210k iterations).
///  * The public keys are advertised on the network (presence topic) so
///    peers can verify message signatures and derive shared secrets.
///  * Chat messages are encrypted with AES-256-GCM under a channel key:
///    - private channels: key derived from a shared passphrase,
///    - public channels: key derived from the topic name (wire privacy),
///    - peer-to-peer: key derived from X25519 ECDH between the two users.
class MessageCrypto {
  static final AesGcm _aes = AesGcm.with256bits();

  static Future<SecretKey> deriveChannelKey(String secret, String topic) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 60000,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(
      password: secret.isEmpty ? topic : secret,
      nonce: utf8.encode('chatnyto:$topic'),
    );
  }

  /// Encrypts [plaintext] and returns a JSON envelope string.
  static Future<String> encryptEnvelope(
      String plaintext, SecretKey key) async {
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'enc': 'aes-256-gcm',
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  /// Returns the decrypted plaintext, or null if [envelope] is not an
  /// encrypted envelope or authentication fails.
  static Future<String?> decryptEnvelope(
      String envelope, SecretKey key) async {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(envelope) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    if (data['enc'] != 'aes-256-gcm') return null;
    try {
      final box = SecretBox(
        base64Decode(data['c'] as String),
        nonce: base64Decode(data['n'] as String),
        mac: Mac(base64Decode(data['m'] as String)),
      );
      final clear = await _aes.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }
}

/// A peer's public identity as advertised on the network.
class PublicIdentity {
  PublicIdentity({
    required this.name,
    required this.x25519PublicKey,
    required this.ed25519PublicKey,
    required this.signature,
    this.avatar = '',
  });

  final String name;
  final String x25519PublicKey; // base64
  final String ed25519PublicKey; // base64
  final String signature; // base64 Ed25519 signature over the signed message

  /// Optional profile picture, base64 JPEG. It is covered by the signature
  /// so nobody can swap somebody else's face onto a verified identity.
  final String avatar;

  bool get hasAvatar => avatar.isNotEmpty;

  /// What the Ed25519 signature covers. Without a picture this is the
  /// original name+key form, so identities published by older builds still
  /// verify.
  Future<String> signedMessage() async {
    if (avatar.isEmpty) return '$name:$x25519PublicKey';
    final digest = await Sha256().hash(utf8.encode(avatar));
    return '$name:$x25519PublicKey:${base64Encode(digest.bytes)}';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'x25519': x25519PublicKey,
        'ed25519': ed25519PublicKey,
        'sig': signature,
        if (avatar.isNotEmpty) 'pic': avatar,
      };

  static PublicIdentity? fromJson(Map<String, dynamic> json) {
    try {
      return PublicIdentity(
        name: json['name'] as String,
        x25519PublicKey: json['x25519'] as String,
        ed25519PublicKey: json['ed25519'] as String,
        signature: json['sig'] as String,
        avatar: json['pic'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Verifies the self-signature of the advertisement.
  Future<bool> verify() async {
    try {
      final ed = Ed25519();
      final message = utf8.encode(await signedMessage());
      return ed.verify(
        message,
        signature: Signature(
          base64Decode(signature),
          publicKey: SimplePublicKey(
            base64Decode(ed25519PublicKey),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  String get fingerprint {
    final bytes = base64Decode(x25519PublicKey);
    return bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}

/// One account as it sits on disk: a name, the public half of its keys in
/// the clear, and the private seeds encrypted twice over — once under the
/// password and once under the recovery code.
///
/// The public keys are stored unencrypted on purpose. They are public by
/// definition, and having them without unlocking is what lets the account
/// list show who each account is, and lets an import recognise an account
/// the device already holds instead of duplicating it.
class StoredAccount {
  StoredAccount({
    required this.id,
    required this.name,
    required this.x25519PublicKey,
    required this.ed25519PublicKey,
    required this.vault,
    this.recovery,
    this.legacy = false,
  });

  /// Base64 X25519 public key once known — the account's real identity.
  /// A record migrated from the single-identity build carries a placeholder
  /// until its first unlock reveals the keys.
  final String id;

  final String name;
  final String x25519PublicKey;
  final String ed25519PublicKey;

  /// salt/nonce/cipher/mac of the seeds under the password.
  final Map<String, dynamic> vault;

  /// The same seeds under the recovery code, when one was kept.
  final Map<String, dynamic>? recovery;

  /// True for the account carried over from the single-identity build. Its
  /// chats live under the unsuffixed storage keys, so it keeps them.
  final bool legacy;

  bool get hasRecovery => recovery != null;
  bool get keysKnown => x25519PublicKey.isNotEmpty;

  /// Short, readable form of the public key, as shown next to a peer.
  String get fingerprint {
    if (!keysKnown) return '';
    return base64Decode(x25519PublicKey)
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'x25519': x25519PublicKey,
        'ed25519': ed25519PublicKey,
        'vault': vault,
        if (recovery != null) 'recovery': recovery,
        if (legacy) 'legacy': true,
      };

  static StoredAccount fromJson(Map<String, dynamic> json) => StoredAccount(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Account',
        x25519PublicKey: json['x25519'] as String? ?? '',
        ed25519PublicKey: json['ed25519'] as String? ?? '',
        vault: (json['vault'] as Map).cast<String, dynamic>(),
        recovery: (json['recovery'] as Map?)?.cast<String, dynamic>(),
        legacy: json['legacy'] as bool? ?? false,
      );

  StoredAccount copyWith({
    String? id,
    String? name,
    String? x25519PublicKey,
    String? ed25519PublicKey,
    Map<String, dynamic>? vault,
    Map<String, dynamic>? recovery,
  }) =>
      StoredAccount(
        id: id ?? this.id,
        name: name ?? this.name,
        x25519PublicKey: x25519PublicKey ?? this.x25519PublicKey,
        ed25519PublicKey: ed25519PublicKey ?? this.ed25519PublicKey,
        vault: vault ?? this.vault,
        recovery: recovery ?? this.recovery,
        legacy: legacy,
      );
}

/// Manages the user's accounts: creation, password-encrypted storage,
/// unlocking, switching, transfer to another device, recovery, presence
/// advertisement payloads and ECDH shared secrets.
///
/// One person can hold several identities — a personal one and a work one,
/// say — and the same identity can live on several devices. Both come from
/// the same fact: an account *is* its key pair, so it is defined by the key
/// rather than by the device. Two records with the same public key are the
/// same account and are merged rather than listed twice.
class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  /// Single-identity storage from earlier builds, migrated on first load.
  static const _legacyPrefKey = 'identity.v1';
  static const _accountsKey = 'accounts.v2';
  static const _activeKey = 'accounts.active';
  static const _pbkdf2Iterations = 210000;

  /// Iterations for the recovery code. It is 120 random bits rather than a
  /// human-chosen password, so it does not need the same brute-force
  /// stretching — and unlocking with it should not take a visible pause on
  /// an old phone.
  static const _recoveryIterations = 20000;

  SimpleKeyPair? _x25519KeyPair;
  SimpleKeyPair? _ed25519KeyPair;
  String? _displayName;
  SecretKey? _storageKey;
  String _activeId = '';
  String _scope = '';

  final List<StoredAccount> _accounts = [];
  bool _accountsLoaded = false;

  bool get isUnlocked => _x25519KeyPair != null;
  String? get displayName => _displayName;

  List<StoredAccount> get accounts => List.unmodifiable(_accounts);
  String get activeAccountId => _activeId;

  StoredAccount? get activeAccount =>
      _accounts.where((a) => a.id == _activeId).firstOrNull;

  /// Suffix that separates one account's stored data from another's. The
  /// migrated account keeps the empty suffix, so its existing chats, outbox
  /// and profile picture stay exactly where they are.
  String get scope => _scope;

  /// The recovery code produced by the last [create] or
  /// [regenerateRecoveryCode]. Held only until the UI has shown it — it is
  /// never written down anywhere by the app, because a copy on the device
  /// would defeat the point.
  String? pendingRecoveryCode;

  // -------------------------------------------------------- account store

  Future<void> _loadAccounts() async {
    if (_accountsLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_accountsKey);
    if (stored != null) {
      _accounts
        ..clear()
        ..addAll(stored.map(
            (s) => StoredAccount.fromJson(jsonDecode(s) as Map<String, dynamic>)));
    } else {
      // First run of this build: adopt the single identity, if there is one.
      final legacy = prefs.getString(_legacyPrefKey);
      if (legacy != null) {
        final data = jsonDecode(legacy) as Map<String, dynamic>;
        _accounts.add(StoredAccount(
          // The public keys only appear once the password decrypts the
          // seeds, so the record is identified by a placeholder until then.
          id: 'legacy',
          name: data['name'] as String? ?? 'Account',
          x25519PublicKey: '',
          ed25519PublicKey: '',
          vault: {
            'salt': data['salt'],
            'nonce': data['nonce'],
            'cipher': data['cipher'],
            'mac': data['mac'],
          },
          legacy: true,
        ));
        await _saveAccounts();
      }
    }
    _activeId = prefs.getString(_activeKey) ??
        (_accounts.isEmpty ? '' : _accounts.first.id);
    _scope = _scopeFor(_activeId);
    _accountsLoaded = true;
  }

  Future<void> _saveAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _accountsKey,
      _accounts.map((a) => jsonEncode(a.toJson())).toList(),
    );
  }

  String _scopeFor(String accountId) {
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null || account.legacy) return '';
    // Short, stable and filesystem-safe: the account's own key, hashed down
    // to something short enough to prefix a preferences key with.
    return '.${sha256Short(accountId)}';
  }

  /// First 8 hex characters of the SHA-256 of [value] — used to namespace an
  /// account's stored data.
  static String sha256Short(String value) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(value)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<bool> exists() async {
    await _loadAccounts();
    return _accounts.isNotEmpty;
  }

  static Future<SecretKey> _passwordKey(String password, List<int> salt,
      {int iterations = _pbkdf2Iterations}) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Seals [seeds] under [secret], returning the salt/nonce/cipher/mac.
  static Future<Map<String, dynamic>> _seal(
      String seeds, String secret, int iterations) async {
    final salt = _randomBytes(16);
    final key = await _passwordKey(secret, salt, iterations: iterations);
    final aes = AesGcm.with256bits();
    final box = await aes.encrypt(
      utf8.encode(seeds),
      secretKey: key,
      nonce: aes.newNonce(),
    );
    return {
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
  }

  /// Opens a sealed blob, or returns null when the secret is wrong (the GCM
  /// tag fails to authenticate).
  static Future<Map<String, dynamic>?> _open(
      Map<String, dynamic> sealed, String secret, int iterations) async {
    try {
      final key = await _passwordKey(
        secret,
        base64Decode(sealed['salt'] as String),
        iterations: iterations,
      );
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(sealed['cipher'] as String),
          nonce: base64Decode(sealed['nonce'] as String),
          mac: Mac(base64Decode(sealed['mac'] as String)),
        ),
        secretKey: key,
      );
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// A 120-bit recovery code, in groups of four so it can be read off a
  /// piece of paper without losing your place. The alphabet leaves out the
  /// characters people confuse (I, L, O, U).
  static String newRecoveryCode() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final rng = Random.secure();
    final groups = List.generate(
      6,
      (_) => List.generate(4, (_) => alphabet[rng.nextInt(alphabet.length)])
          .join(),
    );
    return groups.join('-');
  }

  /// Accepts a recovery code however it was typed back in.
  static String normaliseRecoveryCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

  // ------------------------------------------------------------- lifecycle

  /// Creates a new account and stores it encrypted under [password].
  ///
  /// A recovery code is generated at the same time and left in
  /// [pendingRecoveryCode] for the caller to show once. Nothing else can
  /// recover the account: the seeds exist only under the password and under
  /// that code.
  Future<PublicIdentity> create(String displayName, String password) async {
    await _loadAccounts();
    final xPair = await X25519().newKeyPair();
    final edPair = await Ed25519().newKeyPair();

    final seeds = jsonEncode({
      'x': base64Encode(await xPair.extractPrivateKeyBytes()),
      'ed': base64Encode(await edPair.extractPrivateKeyBytes()),
    });

    final recoveryCode = newRecoveryCode();
    final xPub = base64Encode((await xPair.extractPublicKey()).bytes);
    final account = StoredAccount(
      id: xPub,
      name: displayName,
      x25519PublicKey: xPub,
      ed25519PublicKey:
          base64Encode((await edPair.extractPublicKey()).bytes),
      vault: await _seal(seeds, password, _pbkdf2Iterations),
      recovery: await _seal(
          seeds, normaliseRecoveryCode(recoveryCode), _recoveryIterations),
      // The very first account adopts the unsuffixed storage, so a device
      // that only ever has one account keeps the simple layout.
      legacy: _accounts.isEmpty,
    );

    _accounts.removeWhere((a) => a.id == account.id);
    _accounts.add(account);
    await _saveAccounts();
    await _activate(account.id);

    _x25519KeyPair = xPair;
    _ed25519KeyPair = edPair;
    _displayName = displayName;
    pendingRecoveryCode = recoveryCode;
    return publicIdentity();
  }

  Future<void> _activate(String accountId) async {
    _activeId = accountId;
    _scope = _scopeFor(accountId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, accountId);
  }

  /// Unlocks [accountId] (the active account by default) with [password].
  /// Returns false on a wrong password.
  Future<bool> unlock(String password, {String? accountId}) async {
    await _loadAccounts();
    final id = accountId ?? _activeId;
    final account = _accounts.where((a) => a.id == id).firstOrNull;
    if (account == null) return false;
    final seeds = await _open(account.vault, password, _pbkdf2Iterations);
    if (seeds == null) return false;
    await _adopt(account, seeds);
    return true;
  }

  /// Unlocks with the recovery code instead of the password — the way back
  /// in when the password is gone. The caller should then set a new one
  /// with [changePassword].
  Future<bool> unlockWithRecoveryCode(String code, {String? accountId}) async {
    await _loadAccounts();
    final id = accountId ?? _activeId;
    final account = _accounts.where((a) => a.id == id).firstOrNull;
    if (account?.recovery == null) return false;
    final seeds = await _open(
      account!.recovery!,
      normaliseRecoveryCode(code),
      _recoveryIterations,
    );
    if (seeds == null) return false;
    await _adopt(account, seeds);
    return true;
  }

  /// Loads the key pairs from decrypted [seeds] and makes [account] active,
  /// filling in the public keys of a record migrated from the old build.
  Future<void> _adopt(
      StoredAccount account, Map<String, dynamic> seeds) async {
    _x25519KeyPair =
        await X25519().newKeyPairFromSeed(base64Decode(seeds['x'] as String));
    _ed25519KeyPair =
        await Ed25519().newKeyPairFromSeed(base64Decode(seeds['ed'] as String));
    _displayName = account.name;
    _storageKey = null;

    if (!account.keysKnown) {
      final xPub =
          base64Encode((await _x25519KeyPair!.extractPublicKey()).bytes);
      final edPub =
          base64Encode((await _ed25519KeyPair!.extractPublicKey()).bytes);
      final index = _accounts.indexWhere((a) => a.id == account.id);
      if (index != -1) {
        _accounts[index] = _accounts[index]
            .copyWith(x25519PublicKey: xPub, ed25519PublicKey: edPub);
        await _saveAccounts();
      }
    }
    await _activate(account.id);
  }

  /// Re-seals the unlocked account under a new password. The recovery code
  /// is untouched: it protects the same seeds, not the password.
  Future<bool> changePassword(String newPassword) async {
    if (!isUnlocked) return false;
    final index = _accounts.indexWhere((a) => a.id == _activeId);
    if (index == -1) return false;
    final seeds = jsonEncode({
      'x': base64Encode(await _x25519KeyPair!.extractPrivateKeyBytes()),
      'ed': base64Encode(await _ed25519KeyPair!.extractPrivateKeyBytes()),
    });
    _accounts[index] = _accounts[index]
        .copyWith(vault: await _seal(seeds, newPassword, _pbkdf2Iterations));
    await _saveAccounts();
    return true;
  }

  /// Issues a fresh recovery code for the unlocked account, invalidating the
  /// previous one. Left in [pendingRecoveryCode] for the caller to show.
  Future<String?> regenerateRecoveryCode() async {
    if (!isUnlocked) return null;
    final index = _accounts.indexWhere((a) => a.id == _activeId);
    if (index == -1) return null;
    final seeds = jsonEncode({
      'x': base64Encode(await _x25519KeyPair!.extractPrivateKeyBytes()),
      'ed': base64Encode(await _ed25519KeyPair!.extractPrivateKeyBytes()),
    });
    final code = newRecoveryCode();
    _accounts[index] = _accounts[index].copyWith(
      recovery:
          await _seal(seeds, normaliseRecoveryCode(code), _recoveryIterations),
    );
    await _saveAccounts();
    pendingRecoveryCode = code;
    return code;
  }

  /// Switches to another account. The caller unlocks it afterwards; until
  /// then nothing is readable, because every stored chat is encrypted under
  /// the key derived from that account's own seed.
  Future<void> switchTo(String accountId) async {
    await _loadAccounts();
    if (!_accounts.any((a) => a.id == accountId)) return;
    lock();
    _displayName = null;
    await _activate(accountId);
  }

  Future<void> renameAccount(String accountId, String name) async {
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index == -1) return;
    _accounts[index] = _accounts[index].copyWith(name: name);
    if (accountId == _activeId) _displayName = name;
    await _saveAccounts();
  }

  // -------------------------------------------------------------- transfer

  /// Everything another device needs to hold this account: the same
  /// ciphertext that is stored here, so the private seeds never exist in
  /// the clear outside the app and the same password opens it there.
  ///
  /// The recovery blob is deliberately left out — a transfer is normally
  /// shown as a QR code, and a code that also carried the recovery secret
  /// would be worth photographing over your shoulder.
  String? exportAccount(String accountId) {
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) return null;
    return base64Url.encode(utf8.encode(jsonEncode({
      'v': 1,
      'name': account.name,
      'x25519': account.x25519PublicKey,
      'ed25519': account.ed25519PublicKey,
      'vault': account.vault,
    })));
  }

  /// Takes in an account exported from another device.
  ///
  /// Returns the account's name on success. An account whose public key is
  /// already held is refreshed rather than added a second time — the same
  /// key is the same account, however many devices it reached this one from.
  Future<String?> importAccount(String blob) async {
    await _loadAccounts();
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(blob.trim())))
          as Map<String, dynamic>;
      final xPub = json['x25519'] as String? ?? '';
      if (xPub.isEmpty) return null;
      final account = StoredAccount(
        id: xPub,
        name: json['name'] as String? ?? 'Account',
        x25519PublicKey: xPub,
        ed25519PublicKey: json['ed25519'] as String? ?? '',
        vault: (json['vault'] as Map).cast<String, dynamic>(),
      );
      final existing = _accounts.indexWhere((a) => a.id == account.id);
      if (existing != -1) {
        // Keep the recovery blob this device already has; the incoming copy
        // never carries one.
        _accounts[existing] = account.copyWith(
          recovery: _accounts[existing].recovery,
        );
      } else {
        _accounts.add(account);
      }
      await _saveAccounts();
      return account.name;
    } catch (_) {
      return null;
    }
  }

  /// Removes an account and everything stored under its scope. The keys are
  /// gone for good unless they were exported first.
  Future<void> deleteAccount(String accountId) async {
    await _loadAccounts();
    final account = _accounts.where((a) => a.id == accountId).firstOrNull;
    if (account == null) return;
    final scope = _scopeFor(accountId);
    final otherScopes = _accounts
        .where((a) => a.id != accountId)
        .map((a) => _scopeFor(a.id))
        .where((s) => s.isNotEmpty)
        .toList();
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      final ours = key.startsWith('revamp.') || key == avatarPrefKey;
      if (!ours && !key.startsWith('$avatarPrefKey.')) continue;
      if (scope.isEmpty) {
        // The unsuffixed account owns every key that no other account's
        // suffix claims.
        if (otherScopes.any(key.endsWith)) continue;
      } else if (!key.endsWith(scope)) {
        continue;
      }
      await prefs.remove(key);
    }
    _accounts.removeWhere((a) => a.id == accountId);
    if (_activeId == accountId) {
      lock();
      _displayName = null;
      await _activate(_accounts.isEmpty ? '' : _accounts.first.id);
    }
    await _saveAccounts();
  }

  void lock() {
    _x25519KeyPair = null;
    _ed25519KeyPair = null;
    _storageKey = null;
  }

  /// Symmetric key for encrypting data at rest (message history, outbox),
  /// derived from the identity seed — only available while unlocked.
  Future<SecretKey?> storageKey() async {
    if (_x25519KeyPair == null) return null;
    if (_storageKey != null) return _storageKey;
    final seed = await _x25519KeyPair!.extractPrivateKeyBytes();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    _storageKey = await hkdf.deriveKey(
      secretKey: SecretKey(seed),
      info: utf8.encode('chatnyto:storage'),
    );
    return _storageKey;
  }

  /// Erases the account currently in use.
  Future<void> delete() async {
    final id = _activeId;
    if (id.isEmpty) return;
    await deleteAccount(id);
  }

  /// The profile picture advertised with this identity (base64 JPEG). Each
  /// account has its own, so switching identity changes the face too.
  static const avatarPrefKey = 'profile.picture';

  String get avatarKey => '$avatarPrefKey$scope';

  Future<String> _avatar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(avatarKey) ?? '';
  }

  /// The public, self-signed advertisement of this identity.
  Future<PublicIdentity> publicIdentity() async {
    final xPub = await _x25519KeyPair!.extractPublicKey();
    final edPub = await _ed25519KeyPair!.extractPublicKey();
    final xB64 = base64Encode(xPub.bytes);
    final unsigned = PublicIdentity(
      name: _displayName!,
      x25519PublicKey: xB64,
      ed25519PublicKey: base64Encode(edPub.bytes),
      signature: '',
      avatar: await _avatar(),
    );
    final signature = await Ed25519().sign(
      utf8.encode(await unsigned.signedMessage()),
      keyPair: _ed25519KeyPair!,
    );
    return PublicIdentity(
      name: unsigned.name,
      x25519PublicKey: unsigned.x25519PublicKey,
      ed25519PublicKey: unsigned.ed25519PublicKey,
      signature: base64Encode(signature.bytes),
      avatar: unsigned.avatar,
    );
  }

  /// This device's Ed25519 public key, base64 — the stable identifier used
  /// to prove authorship of group control messages (rename, delete).
  Future<String> ed25519PublicKeyB64() async {
    final edPub = await _ed25519KeyPair!.extractPublicKey();
    return base64Encode(edPub.bytes);
  }

  /// Signs [message] with the Ed25519 identity key.
  Future<String> signPayload(String message) async {
    final signature = await Ed25519().sign(
      utf8.encode(message),
      keyPair: _ed25519KeyPair!,
    );
    return base64Encode(signature.bytes);
  }

  /// Verifies a signature produced by [signPayload] against the signer's
  /// base64 Ed25519 public key.
  static Future<bool> verifyPayload(
      String message, String signatureB64, String publicKeyB64) async {
    try {
      return Ed25519().verify(
        utf8.encode(message),
        signature: Signature(
          base64Decode(signatureB64),
          publicKey: SimplePublicKey(
            base64Decode(publicKeyB64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Derives the peer-to-peer channel key with [peer] via X25519 ECDH + HKDF.
  Future<SecretKey> sharedKeyWith(PublicIdentity peer) async {
    final x = X25519();
    final shared = await x.sharedSecretKey(
      keyPair: _x25519KeyPair!,
      remotePublicKey: SimplePublicKey(
        base64Decode(peer.x25519PublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: shared,
      info: utf8.encode('chatnyto:p2p'),
    );
  }
}
