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
  });

  final String name;
  final String x25519PublicKey; // base64
  final String ed25519PublicKey; // base64
  final String signature; // base64 Ed25519 signature over name+x25519 key

  Map<String, dynamic> toJson() => {
        'name': name,
        'x25519': x25519PublicKey,
        'ed25519': ed25519PublicKey,
        'sig': signature,
      };

  static PublicIdentity? fromJson(Map<String, dynamic> json) {
    try {
      return PublicIdentity(
        name: json['name'] as String,
        x25519PublicKey: json['x25519'] as String,
        ed25519PublicKey: json['ed25519'] as String,
        signature: json['sig'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// Verifies the self-signature of the advertisement.
  Future<bool> verify() async {
    try {
      final ed = Ed25519();
      final message = utf8.encode('$name:$x25519PublicKey');
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

/// Manages the local user identity: creation, password-encrypted storage,
/// unlocking, presence advertisement payloads and ECDH shared secrets.
class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  static const _prefKey = 'identity.v1';
  static const _pbkdf2Iterations = 210000;

  SimpleKeyPair? _x25519KeyPair;
  SimpleKeyPair? _ed25519KeyPair;
  String? _displayName;
  SecretKey? _storageKey;

  bool get isUnlocked => _x25519KeyPair != null;
  String? get displayName => _displayName;

  Future<bool> exists() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_prefKey);
  }

  static Future<SecretKey> _passwordKey(String password, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static List<int> _randomBytes(int length) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Creates a new identity and stores it encrypted under [password].
  Future<PublicIdentity> create(String displayName, String password) async {
    final x = X25519();
    final ed = Ed25519();
    final xPair = await x.newKeyPair();
    final edPair = await ed.newKeyPair();

    final xSeed = await xPair.extractPrivateKeyBytes();
    final edSeed = await edPair.extractPrivateKeyBytes();

    final salt = _randomBytes(16);
    final key = await _passwordKey(password, salt);
    final aes = AesGcm.with256bits();
    final nonce = aes.newNonce();
    final secretJson = jsonEncode({
      'x': base64Encode(xSeed),
      'ed': base64Encode(edSeed),
    });
    final box = await aes.encrypt(
      utf8.encode(secretJson),
      secretKey: key,
      nonce: nonce,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      jsonEncode({
        'name': displayName,
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'cipher': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );

    _x25519KeyPair = xPair;
    _ed25519KeyPair = edPair;
    _displayName = displayName;
    return publicIdentity();
  }

  /// Unlocks the stored identity with [password]. Returns false on a wrong
  /// password (GCM authentication failure).
  Future<bool> unlock(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored == null) return false;
    final data = jsonDecode(stored) as Map<String, dynamic>;
    final key = await _passwordKey(
      password,
      base64Decode(data['salt'] as String),
    );
    final aes = AesGcm.with256bits();
    try {
      final clear = await aes.decrypt(
        SecretBox(
          base64Decode(data['cipher'] as String),
          nonce: base64Decode(data['nonce'] as String),
          mac: Mac(base64Decode(data['mac'] as String)),
        ),
        secretKey: key,
      );
      final seeds = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      _x25519KeyPair =
          await X25519().newKeyPairFromSeed(base64Decode(seeds['x'] as String));
      _ed25519KeyPair = await Ed25519()
          .newKeyPairFromSeed(base64Decode(seeds['ed'] as String));
      _displayName = data['name'] as String;
      return true;
    } catch (_) {
      return false;
    }
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

  Future<void> delete() async {
    lock();
    _displayName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }

  /// The public, self-signed advertisement of this identity.
  Future<PublicIdentity> publicIdentity() async {
    final xPub = await _x25519KeyPair!.extractPublicKey();
    final edPub = await _ed25519KeyPair!.extractPublicKey();
    final xB64 = base64Encode(xPub.bytes);
    final signature = await Ed25519().sign(
      utf8.encode('${_displayName!}:$xB64'),
      keyPair: _ed25519KeyPair!,
    );
    return PublicIdentity(
      name: _displayName!,
      x25519PublicKey: xB64,
      ed25519PublicKey: base64Encode(edPub.bytes),
      signature: base64Encode(signature.bytes),
    );
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
