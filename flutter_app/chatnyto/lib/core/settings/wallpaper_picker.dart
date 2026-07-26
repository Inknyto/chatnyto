import 'package:flutter/material.dart';

import '../theme/background_controller.dart';
import '../widgets/liquid_glass.dart';

/// Grid of bundled background images. Three scopes: the whole app
/// ([forApp]), a single chat ([chatId]), or the global chat default.
class WallpaperPickerPage extends StatelessWidget {
  const WallpaperPickerPage({super.key, this.chatId, this.forApp = false});

  final String? chatId;
  final bool forApp;

  @override
  Widget build(BuildContext context) {
    BackgroundController.instance.load();
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(forApp
              ? 'App wallpaper'
              : chatId == null
                  ? 'Chat wallpaper'
                  : 'Wallpaper for this chat'),
        ),
        body: ValueListenableBuilder<ChatWallpaper>(
          valueListenable: BackgroundController.instance,
          builder: (context, _, __) {
            final selected = forApp
                ? BackgroundController.instance.appWallpaper
                : BackgroundController.instance.forChat(chatId);
            return GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 9 / 14,
              children: [
                for (final wallpaper in ChatWallpaper.all)
                  _WallpaperCard(
                    wallpaper: wallpaper,
                    selected: selected.asset == wallpaper.asset,
                    chatId: chatId,
                    forApp: forApp,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WallpaperCard extends StatelessWidget {
  const _WallpaperCard({
    required this.wallpaper,
    required this.selected,
    this.chatId,
    this.forApp = false,
  });

  final ChatWallpaper wallpaper;
  final bool selected;
  final String? chatId;
  final bool forApp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => forApp
          ? BackgroundController.instance.selectAppWallpaper(wallpaper)
          : chatId == null
              ? BackgroundController.instance.select(wallpaper)
              : BackgroundController.instance
                  .selectForChat(chatId!, wallpaper),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline.withOpacity(0.3),
            width: selected ? 3 : 1,
          ),
          image: wallpaper.asset == null
              ? null
              : DecorationImage(
                  image: AssetImage(wallpaper.asset!),
                  fit: BoxFit.cover,
                ),
          gradient: wallpaper.asset == null
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface,
                    scheme.primaryContainer.withOpacity(0.5),
                  ],
                )
              : null,
        ),
        child: Stack(
          children: [
            if (selected)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(Icons.check_circle_rounded,
                    color: scheme.primary),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: LiquidGlass(
                margin: const EdgeInsets.all(8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                radius: 12,
                child: Text(
                  wallpaper.name,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
