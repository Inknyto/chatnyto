import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls how opaque the liquid-glass surfaces are, persisted across
/// restarts.
///
/// [value] is a 0..1 "solidity" slider: 0 is barely-there glass, 1 is an
/// almost solid panel. The default sits where scrolling content lands —
/// resting surfaces used to be noticeably more transparent than the ones
/// moving under the blur, which read as washed out.
class GlassController extends ValueNotifier<double> {
  GlassController._() : super(defaultSolidity);

  static final GlassController instance = GlassController._();

  static const _prefKey = 'glass.solidity';
  static const defaultSolidity = 0.55;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    value = prefs.getDouble(_prefKey) ?? defaultSolidity;
  }

  Future<void> set(double solidity) async {
    value = solidity.clamp(0.0, 1.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, value);
  }

  /// Surface opacity of a glass panel for the current brightness.
  double surfaceOpacity(bool isDark) =>
      isDark ? 0.04 + 0.30 * value : 0.28 + 0.50 * value;

  /// Border opacity, kept in step with the surface so the edge highlight
  /// never outshines the panel.
  double borderOpacity(bool isDark) =>
      isDark ? 0.10 + 0.20 * value : 0.35 + 0.45 * value;

  /// Human-readable label for the settings screen.
  String get label {
    if (value < 0.25) return 'Very transparent';
    if (value < 0.45) return 'Transparent';
    if (value < 0.7) return 'Balanced';
    if (value < 0.9) return 'Solid';
    return 'Very solid';
  }
}
