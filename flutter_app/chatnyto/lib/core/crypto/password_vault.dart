import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto_service.dart';

/// Remembers the identity password so the app opens straight into the
/// chats, and lets the user turn that off.
///
/// The password is kept by the platform's secure storage (Android Keystore
/// backed EncryptedSharedPreferences, iOS/macOS Keychain, libsecret on
/// Linux, DPAPI on Windows) — never in the app's own preferences, so an
/// extracted data backup does not reveal it.
class PasswordVault {
  PasswordVault._();

  static final PasswordVault instance = PasswordVault._();

  static const _askEveryTimeKey = 'security.askPasswordEveryOpen';
  static const _secureKey = 'identity.password';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// When true the password is never stored and is asked for at every
  /// app open. Off by default: the password is remembered.
  Future<bool> askEveryOpen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_askEveryTimeKey) ?? false;
  }

  Future<void> setAskEveryOpen(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askEveryTimeKey, value);
    if (value) await forget();
  }

  /// Stores [password] unless the user asked to be prompted every time.
  Future<void> remember(String password) async {
    if (await askEveryOpen()) return;
    try {
      await _storage.write(key: _secureKey, value: password);
    } catch (error) {
      // No secure backend on this platform/session: simply don't remember.
      debugPrint('Could not store the password securely: $error');
    }
  }

  Future<void> forget() async {
    try {
      await _storage.delete(key: _secureKey);
    } catch (error) {
      debugPrint('Could not clear the stored password: $error');
    }
  }

  Future<bool> hasRemembered() async {
    if (await askEveryOpen()) return false;
    try {
      return await _storage.read(key: _secureKey) != null;
    } catch (_) {
      return false;
    }
  }

  /// Unlocks the identity with the remembered password. Returns false when
  /// nothing is stored, the backend is unavailable, or the stored password
  /// no longer matches (it is then dropped).
  Future<bool> tryAutoUnlock() async {
    if (IdentityService.instance.isUnlocked) return true;
    if (await askEveryOpen()) return false;
    String? password;
    try {
      password = await _storage.read(key: _secureKey);
    } catch (error) {
      debugPrint('Secure storage unavailable: $error');
      return false;
    }
    if (password == null) return false;
    final unlocked = await IdentityService.instance.unlock(password);
    if (!unlocked) await forget();
    return unlocked;
  }
}
