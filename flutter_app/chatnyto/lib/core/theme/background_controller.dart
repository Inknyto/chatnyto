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
class BackgroundController extends ValueNotifier<ChatWallpaper> {
  BackgroundController._() : super(ChatWallpaper.none);

  static final BackgroundController instance = BackgroundController._();

  static const _prefKey = 'chat.wallpaper';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    value = ChatWallpaper.all.firstWhere(
      (w) => w.asset == stored,
      orElse: () => ChatWallpaper.none,
    );
  }

  Future<void> select(ChatWallpaper wallpaper) async {
    value = wallpaper;
    final prefs = await SharedPreferences.getInstance();
    if (wallpaper.asset == null) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, wallpaper.asset!);
    }
  }
}

/// Paints the selected wallpaper behind [child]; falls back to nothing
/// (transparent) when no wallpaper is selected.
class WallpaperBackdrop extends StatelessWidget {
  const WallpaperBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    BackgroundController.instance.load();
    return ValueListenableBuilder<ChatWallpaper>(
      valueListenable: BackgroundController.instance,
      builder: (context, wallpaper, _) {
        if (wallpaper.asset == null) return child;
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
