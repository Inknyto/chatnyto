import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/brokers/broker_service.dart';
import '../core/brokers/brokers_page.dart';
import '../core/crypto/crypto_service.dart';
import '../core/crypto/password_vault.dart';
import '../core/media/image_service.dart';
import '../core/notifications/background_service.dart';
import '../core/notifications/notification_service.dart';
import '../core/settings/wallpaper_picker.dart';
import '../core/theme/background_controller.dart';
import '../core/theme/glass_controller.dart';
import '../core/theme/locale_controller.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/liquid_glass.dart';
import '../l10n/app_localizations.dart';
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
  bool _askPassword = false;
  bool _autoConnect = true;
  String _avatar = '';
  NotificationSound _sound = NotificationSound.chime;
  bool _stayConnected = true;
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
    await GlassController.instance.load();
    final askPassword = await PasswordVault.instance.askEveryOpen();
    final autoConnect = await BrokerService.instance.autoConnectEnabled();
    final sound = await NotificationService.instance.sound();
    final stayConnected = await BackgroundService.instance.enabled();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sound = sound;
      _stayConnected = stayConnected;
      _askPassword = askPassword;
      _autoConnect = autoConnect;
      _avatar = prefs.getString(IdentityService.avatarPrefKey) ?? '';
      _name = prefs.getString('profile.name') ?? '';
      _email = prefs.getString('profile.email') ?? '';
      _phone = prefs.getString('profile.phone') ?? '';
      _language = LocaleController.instance
          .labelFor(LocaleController.instance.value, systemLabel: 'System');
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

  /// Picks the alert tone; choosing one plays it so it can be heard.
  Future<void> _pickSound() async {
    final choice = await showDialog<NotificationSound>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).notificationSound),
        children: [
          for (final sound in NotificationSound.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, sound),
              child: Row(
                children: [
                  Icon(
                    sound == _sound
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(sound.label),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await NotificationService.instance.setSound(choice);
    if (mounted) setState(() => _sound = choice);
  }

  /// Switches the whole app between English, French and the phone's own
  /// language; the choice is persisted and applied immediately.
  Future<void> _pickLanguage() async {
    final systemLabel = AppLocalizations.of(context).languageSystem;
    final options = <Locale?>[null, ...LocaleController.supported];
    final choice = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocalizations.of(context).language),
        children: [
          for (final locale in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop<Object>(
                  context, locale ?? const Object()),
              child: Text(LocaleController.instance
                  .labelFor(locale, systemLabel: systemLabel)),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final locale = choice is Locale ? choice : null;
    await LocaleController.instance.setLocale(locale);
    if (mounted) {
      setState(() => _language = LocaleController.instance
          .labelFor(locale, systemLabel: systemLabel));
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

  /// Profile picture: stored locally and advertised (signed) with the
  /// identity, so contacts see a face next to the verified fingerprint.
  Widget _profilePictureTile() {
    final picture = ImageService.decode(_avatar);
    return LiquidGlass(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: picture == null ? null : MemoryImage(picture),
            child: picture == null
                ? const Icon(Icons.person_rounded, size: 30)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(AppLocalizations.of(context).profilePicture,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (_avatar.isNotEmpty)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _setAvatar(''),
            ),
          IconButton(
            tooltip: 'Change',
            icon: const Icon(Icons.photo_camera_rounded),
            onPressed: _pickAvatar,
          ),
        ],
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final encoded = await ImageService.instance.pickAsBase64(
      fromCamera: false,
      maxEdge: ImageService.avatarMaxEdge,
      quality: 60,
    );
    if (encoded != null) await _setAvatar(encoded);
  }

  Future<void> _setAvatar(String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(IdentityService.avatarPrefKey);
    } else {
      await prefs.setString(IdentityService.avatarPrefKey, value);
    }
    // Re-publish the identity so contacts pick the new picture up.
    await BrokerService.instance.advertiseEverywhere();
    if (mounted) setState(() => _avatar = value);
  }

  /// Slider controlling how solid every glass surface looks; persisted, so
  /// the whole app keeps the chosen shade after a restart.
  Widget _glassOpacityTile() {
    return ValueListenableBuilder<double>(
      valueListenable: GlassController.instance,
      builder: (context, solidity, _) => LiquidGlass(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.opacity_rounded),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(AppLocalizations.of(context).glassOpacity)),
                Text(GlassController.instance.label,
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
            Slider(
              value: solidity,
              onChanged: (value) => GlassController.instance.set(value),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                AppLocalizations.of(context).glassOpacityHelp,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
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
    final l10n = AppLocalizations.of(context);
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(l10n.menuSettings),
        ),
        body: SettingsList(
          lightTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          darkTheme:
              const SettingsThemeData(settingsListBackground: Colors.transparent),
          sections: [
            SettingsSection(
              title: Text(l10n.settingsProfile),
              tiles: <AbstractSettingsTile>[
                CustomSettingsTile(child: _profilePictureTile()),
                SettingsTile.navigation(
                  leading: const Icon(Icons.person_rounded),
                  title: Text(l10n.displayName),
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
              title: Text(l10n.settingsSecurity),
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
                  onToggle: (value) async {
                    await PasswordVault.instance.setAskEveryOpen(value);
                    if (mounted) setState(() => _askPassword = value);
                  },
                  initialValue: _askPassword,
                  leading: const Icon(Icons.password_rounded),
                  title: Text(l10n.askPasswordEveryOpen),
                  description: Text(_askPassword
                      ? 'You unlock the app by hand each time.'
                      : 'Your password is kept in the device keystore so '
                          'the app opens straight into your chats.'),
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
              title: Text(l10n.networks),
              tiles: <SettingsTile>[
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await BrokerService.instance
                        .setAutoConnectEnabled(value);
                    if (mounted) setState(() => _autoConnect = value);
                  },
                  initialValue: _autoConnect,
                  leading: const Icon(Icons.autorenew_rounded),
                  title: Text(l10n.connectAutomatically),
                  description: const Text(
                      'Reconnects your networks as soon as they are '
                      'reachable.'),
                ),
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await BackgroundService.instance.setEnabled(value);
                    if (mounted) setState(() => _stayConnected = value);
                  },
                  initialValue: _stayConnected,
                  leading: const Icon(Icons.play_circle_outline_rounded),
                  title: Text(l10n.stayConnected),
                  description: Text(l10n.stayConnectedHelp),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.dns_rounded),
                  title: Text(l10n.networks),
                  description:
                      const Text('Add, find and edit brokers'),
                  onPressed: (context) => Navigator.push(
                    context,
                    GlassPageRoute(page: const BrokersPage()),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: Text(l10n.settingsNotifications),
              tiles: <SettingsTile>[
                SettingsTile.switchTile(
                  onToggle: (value) async {
                    await _setBool('notifications', value);
                    if (value) {
                      await NotificationService.instance.init();
                      await NotificationService.instance.requestPermission();
                    }
                    if (mounted) {
                      setState(() => _notificationsEnabled = value);
                    }
                  },
                  initialValue: _notificationsEnabled,
                  leading: const Icon(Icons.notifications_rounded),
                  title: Text(l10n.messageNotifications),
                  description: Text(l10n.messageNotificationsHelp),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.music_note_rounded),
                  title: Text(l10n.notificationSound),
                  value: Text(_sound.label),
                  onPressed: (_) => _pickSound(),
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
              title: Text(l10n.settingsPreferences),
              tiles: <AbstractSettingsTile>[
                SettingsTile.navigation(
                  leading: const Icon(Icons.language_rounded),
                  title: Text(l10n.language),
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
                  title: Text(l10n.darkMode),
                ),
                SettingsTile.navigation(
                  leading: const Icon(Icons.wallpaper_rounded),
                  title: Text(l10n.chatWallpaper),
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
                  title: Text(l10n.appWallpaper),
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
                CustomSettingsTile(child: _glassOpacityTile()),
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
