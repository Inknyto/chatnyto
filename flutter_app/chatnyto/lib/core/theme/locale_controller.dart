import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's language: English, French, or whatever the phone is set to.
/// Persisted, so the choice survives a restart.
class LocaleController extends ValueNotifier<Locale?> {
  LocaleController._() : super(null);

  static final LocaleController instance = LocaleController._();

  static const _prefKey = 'language';

  /// Locales the app ships translations for.
  static const supported = [Locale('en'), Locale('fr')];

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    value = _parse(prefs.getString(_prefKey));
  }

  /// Accepts a language code, and also the display names the older builds
  /// stored under the same preference key.
  static Locale? _parse(String? stored) {
    switch (stored) {
      case 'en':
      case 'English':
        return const Locale('en');
      case 'fr':
      case 'Français':
        return const Locale('fr');
      default:
        return null; // follow the system
    }
  }

  /// Pass null to follow the phone's language.
  Future<void> setLocale(Locale? locale) async {
    value = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, locale.languageCode);
    }
  }

  /// Name to show in the settings, in the language it names.
  String labelFor(Locale? locale, {required String systemLabel}) {
    switch (locale?.languageCode) {
      case 'en':
        return 'English';
      case 'fr':
        return 'Français';
      default:
        return systemLabel;
    }
  }
}
