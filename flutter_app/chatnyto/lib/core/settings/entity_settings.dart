import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/background_controller.dart';
import '../theme/theme_controller.dart';
import '../widgets/liquid_glass.dart';
import 'wallpaper_picker.dart';

/// Shared parameters page used by the humans, robots and AIs sections.
class EntitySettings extends StatefulWidget {
  const EntitySettings({super.key, this.title = 'Parameters'});

  final String title;

  @override
  State<EntitySettings> createState() => _EntitySettingsState();
}

class _EntitySettingsState extends State<EntitySettings> {
  static const _languages = ['English', 'Français'];
  String _language = 'English';
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await BackgroundController.instance.load();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _language = prefs.getString('language') ?? 'English';
      _notifications = prefs.getBool('notifications') ?? true;
    });
  }

  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language'),
        children: [
          for (final lang in _languages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, lang),
              child: Text(lang),
            ),
        ],
      ),
    );
    if (choice != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('language', choice);
      if (mounted) setState(() => _language = choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(widget.title)),
        body: SettingsList(
          lightTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          darkTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          sections: [
            SettingsSection(
              title: const Text('Appearance'),
              tiles: <SettingsTile>[
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await ThemeController.instance
                        .setMode(value ? ThemeMode.dark : ThemeMode.light);
                    if (mounted) setState(() {});
                  },
                  initialValue: isDark,
                  leading: const Icon(Icons.dark_mode_rounded),
                  title: const Text('Dark mode'),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.wallpaper_rounded),
                  title: const Text('Chat wallpaper'),
                  value: ValueListenableBuilder<ChatWallpaper>(
                    valueListenable: BackgroundController.instance,
                    builder: (context, wallpaper, _) =>
                        Text(wallpaper.name),
                  ),
                  onPressed: (context) => Navigator.push(
                    context,
                    GlassPageRoute(page: const WallpaperPickerPage()),
                  ),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.image_rounded),
                  title: const Text('App wallpaper'),
                  value: ValueListenableBuilder<ChatWallpaper>(
                    valueListenable: BackgroundController.instance,
                    builder: (context, _, __) => Text(
                        BackgroundController.instance.appWallpaper.name),
                  ),
                  onPressed: (context) => Navigator.push(
                    context,
                    GlassPageRoute(
                        page: const WallpaperPickerPage(forApp: true)),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Common'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  value: Text(_language),
                  onPressed: (_) => _pickLanguage(),
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('notifications', value);
                    if (mounted) setState(() => _notifications = value);
                  },
                  initialValue: _notifications,
                  leading: const Icon(Icons.notifications_rounded),
                  title: const Text('Notifications'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
