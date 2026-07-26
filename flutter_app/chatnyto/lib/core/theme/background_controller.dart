import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A selectable chat wallpaper bundled with the app.
class ChatWallpaper {
  const ChatWallpaper(this.name, this.asset);

  final String name;
  final String? asset; // null = plain glass gradient, no image

  static const none = ChatWallpaper('None (glass)', null);

  static const all = [
    none,
    ChatWallpaper('Midnight doodle', 'assets/backgrounds/midnight_doodle.png'),
    ChatWallpaper('Aurora', 'assets/backgrounds/aurora.png'),
    ChatWallpaper('Sunset glass', 'assets/backgrounds/sunset_glass.png'),
    ChatWallpaper('Paper light', 'assets/backgrounds/paper_light.png'),
    ChatWallpaper('Forest', 'assets/backgrounds/forest.png'),
  ];
}

/// Persisted custom background image selection, applied to chat screens.
/// Supports one global wallpaper plus optional per-chat overrides.
class BackgroundController extends ValueNotifier<ChatWallpaper> {
  BackgroundController._() : super(ChatWallpaper.none);

  static final BackgroundController instance = BackgroundController._();

  static const _prefKey = 'chat.wallpaper';
  static const _appPrefKey = 'app.wallpaper';
  static const _chatPrefPrefix = 'chat.wallpaper.of.';
  bool _loaded = false;
  final Map<String, String> _perChat = {};
  ChatWallpaper _app = ChatWallpaper.none;

  /// Wallpaper painted under the whole app (all glass surfaces).
  ChatWallpaper get appWallpaper => _app;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    _app = _byAsset(prefs.getString(_appPrefKey));
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_chatPrefPrefix)) {
        _perChat[key.substring(_chatPrefPrefix.length)] =
            prefs.getString(key)!;
      }
    }
    value = _byAsset(stored);
    notifyListeners();
  }

  Future<void> selectAppWallpaper(ChatWallpaper wallpaper) async {
    _app = wallpaper;
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper.asset == null) {
      await prefs.remove(_appPrefKey);
    } else {
      await prefs.setString(_appPrefKey, wallpaper.asset!);
    }
    notifyListeners();
  }

  static ChatWallpaper _byAsset(String? asset) => ChatWallpaper.all.firstWhere(
        (w) => w.asset == asset,
        orElse: () => ChatWallpaper.none,
      );

  /// Effective wallpaper for [chatId] (per-chat override, else global).
  ChatWallpaper forChat(String? chatId) {
    if (chatId != null && _perChat.containsKey(chatId)) {
      return _byAsset(_perChat[chatId]);
    }
    return value;
  }

  bool hasOverride(String chatId) => _perChat.containsKey(chatId);

  Future<void> select(ChatWallpaper wallpaper) async {
    value = wallpaper;
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper.asset == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, wallpaper.asset!);
    }
    notifyListeners();
  }

  /// Sets a per-chat override; pass null wallpaper to clear the override.
  Future<void> selectForChat(String chatId, ChatWallpaper? wallpaper) async {
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper == null) {
      _perChat.remove(chatId);
      await prefs.remove('$_chatPrefPrefix$chatId');
    } else {
      _perChat[chatId] = wallpaper.asset ?? '';
      await prefs.setString('$_chatPrefPrefix$chatId', wallpaper.asset ?? '');
    }
    notifyListeners();
  }
}

/// Paints the selected wallpaper behind [child]; falls back to nothing
/// (transparent) when no wallpaper is selected. Pass [chatId] to honor a
/// per-chat override.
class WallpaperBackdrop extends StatelessWidget {
  const WallpaperBackdrop({super.key, required this.child, this.chatId});

  final Widget child;
  final String? chatId;

  @override
  Widget build(BuildContext context) {
    BackgroundController.instance.load();
    return ValueListenableBuilder<ChatWallpaper>(
      valueListenable: BackgroundController.instance,
      builder: (context, _, __) {
        final wallpaper = BackgroundController.instance.forChat(chatId);
        if (wallpaper.asset == null || wallpaper.asset!.isEmpty) return child;
        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(wallpaper.asset!),
              fit: BoxFit.cover,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
