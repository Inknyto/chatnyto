import 'dart:convert';

import 'package:chatnyto/core/crypto/crypto_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifying a peer's advertisement is Ed25519 over a pure-Dart curve, and
/// presence is retained — so the same advertisement arrives again on every
/// reconnection to every broker. The result is cached. These are the tests
/// that the cache did not become a hole.
Future<PublicIdentity> _sign({
  required String name,
  required String avatar,
  SimpleKeyPair? with_,
}) async {
  final ed = Ed25519();
  final edPair = with_ ?? await ed.newKeyPair();
  final edPub = await edPair.extractPublicKey();
  // The X25519 half is not exercised here; any 32 bytes stand in for it.
  final x = base64Encode(List<int>.filled(32, 7));
  final unsigned = PublicIdentity(
    name: name,
    x25519PublicKey: x,
    ed25519PublicKey: base64Encode(edPub.bytes),
    signature: '',
    avatar: avatar,
  );
  final signature = await ed.sign(
    utf8.encode(await unsigned.signedMessage()),
    keyPair: edPair,
  );
  return PublicIdentity(
    name: name,
    x25519PublicKey: x,
    ed25519PublicKey: base64Encode(edPub.bytes),
    signature: base64Encode(signature.bytes),
    avatar: avatar,
  );
}

void main() {
  test('a genuine advertisement verifies', () async {
    final identity = await _sign(name: 'Ada', avatar: '');
    expect(await identity.verify(), isTrue);
  });

  test('the same advertisement verifies again, and the answer is stable',
      () async {
    // The second call is the cached one. It must agree with the first.
    final identity = await _sign(name: 'Ada', avatar: 'AAAA');
    expect(await identity.verify(), isTrue);
    expect(await identity.verify(), isTrue);
  });

  test('a swapped name is refused even after the real one was accepted',
      () async {
    final real = await _sign(name: 'Ada', avatar: '');
    expect(await real.verify(), isTrue);
    final forged = PublicIdentity(
      name: 'Mallory',
      x25519PublicKey: real.x25519PublicKey,
      ed25519PublicKey: real.ed25519PublicKey,
      signature: real.signature,
    );
    expect(await forged.verify(), isFalse);
  });

  test('a picture swapped for another of the same length is refused',
      () async {
    // The cache used to be keyed on the picture length rather than its
    // content, which made exactly this substitution pass once the genuine
    // advertisement had been seen.
    final real = await _sign(name: 'Ada', avatar: base64Encode([1, 2, 3]));
    expect(await real.verify(), isTrue);
    final forged = PublicIdentity(
      name: real.name,
      x25519PublicKey: real.x25519PublicKey,
      ed25519PublicKey: real.ed25519PublicKey,
      signature: real.signature,
      avatar: base64Encode([9, 9, 9]),
    );
    expect(forged.avatar.length, real.avatar.length);
    expect(await forged.verify(), isFalse);
  });

  test('a signature from a different key is refused', () async {
    final ada = await _sign(name: 'Ada', avatar: '');
    final mallory = await _sign(name: 'Ada', avatar: '');
    final forged = PublicIdentity(
      name: 'Ada',
      x25519PublicKey: ada.x25519PublicKey,
      ed25519PublicKey: ada.ed25519PublicKey,
      signature: mallory.signature,
    );
    expect(await forged.verify(), isFalse);
  });

  test('a refusal is remembered as a refusal, not as an answer', () async {
    final bad = PublicIdentity(
      name: 'Ada',
      x25519PublicKey: base64Encode(List<int>.filled(32, 7)),
      ed25519PublicKey: base64Encode(List<int>.filled(32, 3)),
      signature: base64Encode(List<int>.filled(64, 0)),
    );
    expect(await bad.verify(), isFalse);
    expect(await bad.verify(), isFalse);
  });
}
