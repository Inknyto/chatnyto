import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This device's adb identity.
///
/// Every adb connection is authenticated the same way: the device sends a
/// twenty-byte token, and whoever wants in signs it with an RSA-2048 private
/// key. If the device has not seen the matching public key before it shows
/// the "Allow debugging?" dialog with a fingerprint on it, and the person at
/// the television decides. That is the whole security model, and it is why
/// this app has to hold a key rather than borrowing one.
///
/// The key is generated once and kept, because it is what "always allow from
/// this computer" is remembering. Regenerating it would make every
/// television, phone and box ask again, and would make the fingerprint the
/// user was shown meaningless.
class AdbKey {
  AdbKey._(this._private, this._public);

  final RSAPrivateKey _private;
  final RSAPublicKey _public;

  static const _privateKeyPref = 'adb.key.v1';
  static AdbKey? _cached;

  /// Loads the key, generating one the first time.
  ///
  /// Generation is 2048-bit RSA in pure Dart, which takes seconds — and
  /// seconds on the main isolate is the difference between an app and an
  /// "isn't responding" dialog. It happens on a background isolate, once,
  /// ever.
  static Future<AdbKey> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_privateKeyPref);
    if (stored != null) {
      final key = _decode(stored);
      if (key != null) return _cached = key;
    }
    final parts = await compute(_generate, DateTime.now().microsecondsSinceEpoch);
    await prefs.setString(_privateKeyPref, jsonEncode(parts));
    return _cached = _fromParts(parts)!;
  }

  /// Wipes the identity. The next connection to anything will ask for
  /// permission again, which is the point: this is how a user revokes what
  /// they granted.
  static Future<void> forget() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_privateKeyPref);
  }

  // ------------------------------------------------------------ signing

  /// Signs adbd's challenge.
  ///
  /// The token *is* a SHA-1 digest already, so it is wrapped in the SHA-1
  /// DigestInfo and padded, rather than hashed again. Signing the hash of
  /// the hash produces a perfectly valid signature of the wrong thing, and
  /// adbd answers it by asking for the token once more — which looks exactly
  /// like a key it has never seen.
  Uint8List sign(Uint8List token) {
    const sha1DigestInfo = [
      0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e,
      0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14, //
    ];
    final wrapped = Uint8List.fromList([...sha1DigestInfo, ...token]);
    // PKCS#1 v1.5, type 1 padding — which is what pointycastle's
    // PKCS1Encoding produces when it is initialised with a private key.
    final engine = PKCS1Encoding(RSAEngine())
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(_private));
    return engine.process(wrapped);
  }

  /// The public key in the shape adbd expects, ready to send.
  ///
  /// Not any standard encoding: Android has its own 524-byte structure, laid
  /// out for a bootloader that verifies signatures with 32-bit arithmetic
  /// and no bignum library. It carries the modulus little-endian, plus two
  /// values precomputed so the verifier does not have to — the Montgomery
  /// constant n0inv and the reduction factor rr.
  String get androidPublicKey =>
      '${base64Encode(publicKeyBlob(_public.modulus!, _public.exponent!))} '
      // The trailing name is what the device shows beside the fingerprint in
      // its "allow debugging" dialog, so it says who is asking.
      'chatnyto@android';

  /// Builds the 524-byte structure. Separated from the key it describes so
  /// the arithmetic can be checked without generating one — this is the part
  /// that fails silently, because adbd's only response to a malformed key is
  /// to ask for the token again, which looks exactly like a key it has not
  /// seen before.
  @visibleForTesting
  static Uint8List publicKeyBlob(BigInt modulus, BigInt exponent) {
    final blob = ByteData(524);
    const words = 64; // 2048 bits / 32
    blob.setUint32(0, words, Endian.little);
    blob.setUint32(4, n0inv(modulus), Endian.little);
    _writeLittleEndian(blob, 8, modulus, 256);
    // rr = (2^32)^(2*64) mod n = 2^4096 mod n
    final rr = (BigInt.one << 4096) % modulus;
    _writeLittleEndian(blob, 264, rr, 256);
    blob.setUint32(520, exponent.toInt(), Endian.little);
    return blob.buffer.asUint8List();
  }

  /// -1/n mod 2^32, as the Android structure wants it.
  @visibleForTesting
  static int n0inv(BigInt modulus) {
    final base = BigInt.one << 32;
    final n0 = modulus % base;
    final inverse = n0.modInverse(base);
    return (base - inverse).toInt();
  }

  static void _writeLittleEndian(
      ByteData out, int offset, BigInt value, int length) {
    var rest = value;
    final byte = BigInt.from(0xff);
    for (var i = 0; i < length; i++) {
      out.setUint8(offset + i, (rest & byte).toInt());
      rest = rest >> 8;
    }
  }

  // --------------------------------------------------------- persistence

  static Map<String, String> _toParts(RSAPrivateKey key) => {
        'n': key.modulus!.toString(),
        'e': key.publicExponent!.toString(),
        'd': key.privateExponent!.toString(),
        'p': key.p!.toString(),
        'q': key.q!.toString(),
      };

  static AdbKey? _fromParts(Map<String, String> parts) {
    try {
      final n = BigInt.parse(parts['n']!);
      final e = BigInt.parse(parts['e']!);
      return AdbKey._(
        RSAPrivateKey(n, BigInt.parse(parts['d']!), BigInt.parse(parts['p']!),
            BigInt.parse(parts['q']!)),
        RSAPublicKey(n, e),
      );
    } catch (_) {
      return null;
    }
  }

  static AdbKey? _decode(String stored) {
    try {
      return _fromParts(
          Map<String, String>.from(jsonDecode(stored) as Map));
    } catch (_) {
      return null;
    }
  }

  /// Runs on a background isolate, so its arguments and result have to be
  /// plain data — hence the map of decimal strings rather than a key object.
  static Map<String, String> _generate(int seed) {
    final random = Random.secure();
    final entropy = Uint8List(32);
    for (var i = 0; i < entropy.length; i++) {
      entropy[i] = random.nextInt(256);
    }
    // Seeded from the platform's own generator; the timestamp only makes two
    // isolates started in the same instant differ.
    entropy[0] ^= seed & 0xff;
    final secure = FortunaRandom()..seed(KeyParameter(entropy));
    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        secure,
      ));
    final pair = generator.generateKeyPair();
    return _toParts(pair.privateKey);
  }
}
