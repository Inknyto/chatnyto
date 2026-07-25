import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/settings/wallpaper_picker.dart';
import '../core/theme/background_controller.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/liquid_glass.dart';
import 'security_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _notificationsEnabled = true;
  bool _biometricsEnabled = false;
  bool _locationEnabled = false;
  String _name = '';
  String _email = '';
  String _phone = '';
  String _language = 'English';

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
      _name = prefs.getString('profile.name') ?? '';
      _email = prefs.getString('profile.email') ?? '';
      _phone = prefs.getString('profile.phone') ?? '';
      _language = prefs.getString('language') ?? 'English';
      _notificationsEnabled = prefs.getBool('notifications') ?? true;
      _biometricsEnabled = prefs.getBool('biometrics') ?? false;
      _locationEnabled = prefs.getBool('location') ?? false;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _editField({
    required String title,
    required String prefKey,
    required String current,
    required void Function(String) apply,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, controller.text.trim());
      if (mounted) setState(() => apply(controller.text.trim()));
    }
  }

  Future<void> _pickLanguage() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language'),
        children: [
          for (final lang in const ['English', 'Français'])
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

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This removes your profile, saved connections, message history '
            'and encrypted identity from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        setState(() {
          _name = '';
          _email = '';
          _phone = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All local account data deleted.')),
        );
      }
    }
  }

  void _showInfo(String title, String body) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Account Settings'),
        ),
        body: SettingsList(
          lightTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          darkTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          sections: [
            SettingsSection(
              title: const Text('Profile'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.person_rounded),
                  title: const Text('Display name'),
                  value: Text(_name.isEmpty ? 'Not set' : _name),
                  onPressed: (_) => _editField(
                    title: 'Display name',
                    prefKey: 'profile.name',
                    current: _name,
                    apply: (v) => _name = v,
                  ),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.email_rounded),
                  title: const Text('Email'),
                  value: Text(_email.isEmpty ? 'Not set' : _email),
                  onPressed: (_) => _editField(
                    title: 'Email',
                    prefKey: 'profile.email',
                    current: _email,
                    apply: (v) => _email = v,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.phone_rounded),
                  title: const Text('Phone'),
                  value: Text(_phone.isEmpty ? 'Not set' : _phone),
                  onPressed: (_) => _editField(
                    title: 'Phone',
                    prefKey: 'profile.phone',
                    current: _phone,
                    apply: (v) => _phone = v,
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Security'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.shield_rounded),
                  title: const Text('Keys & encryption'),
                  description:
                      const Text('Identity, public key, password'),
                  onPressed: (context) => Navigator.push(
                    context,
                    GlassPageRoute(page: const SecurityPage()),
                  ),
                ),
                SettingsTile.switchTile(
                  onToggle: (value) {
                    _setBool('biometrics', value);
                    setState(() => _biometricsEnabled = value);
                  },
                  initialValue: _biometricsEnabled,
                  leading: const Icon(Icons.fingerprint_rounded),
                  title: const Text('Enable Biometrics'),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Notifications'),
              tiles: <SettingsTile>[
                SettingsTile.switchTile(
                  onToggle: (value) {
                    _setBool('notifications', value);
                    setState(() => _notificationsEnabled = value);
                  },
                  initialValue: _notificationsEnabled,
                  leading: const Icon(Icons.notifications_rounded),
                  title: const Text('Push Notifications'),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Privacy'),
              tiles: <SettingsTile>[
                SettingsTile.switchTile(
                  onToggle: (value) {
                    _setBool('location', value);
                    setState(() => _locationEnabled = value);
                  },
                  initialValue: _locationEnabled,
                  leading: const Icon(Icons.location_on_rounded),
                  title: const Text('Location Services'),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.delete_rounded),
                  title: const Text('Delete Account'),
                  onPressed: (_) => _deleteAccount(),
                ),
              ],
            ),
            SettingsSection(
              title: const Text('Preferences'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Language'),
                  value: Text(_language),
                  onPressed: (_) => _pickLanguage(),
                ),
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
              ],
            ),
            SettingsSection(
              title: const Text('About'),
              tiles: <SettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.info_rounded),
                  title: const Text('App Version'),
                  value: const Text('1.0.1'),
                  onPressed: (_) => _showInfo(
                    'ChatNyto 1.0.1',
                    'Chat with humans, robots and AIs over MQTT — with or '
                        'without internet (LoRa broker on Heltec V3).',
                  ),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.description_rounded),
                  title: const Text('Terms of Service'),
                  onPressed: (_) => _showInfo(
                    'Terms of Service',
                    'ChatNyto is provided as-is, without warranty. You are '
                        'responsible for the messages you send and for '
                        'complying with local radio regulations when using '
                        'LoRa brokers.',
                  ),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.privacy_tip_rounded),
                  title: const Text('Privacy Policy'),
                  onPressed: (_) => _showInfo(
                    'Privacy Policy',
                    'All data stays on your device. Messages are encrypted '
                        'end-to-end; brokers only relay ciphertext. No data '
                        'is collected by the app authors.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
