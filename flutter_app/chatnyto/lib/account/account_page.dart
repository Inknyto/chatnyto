import 'package:flutter/material.dart';
import 'package:settings_ui/settings_ui.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _customThemeEnabled = true;
  bool _notificationsEnabled = true;
  bool _biometricsEnabled = true;
  bool _locationEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
      ),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('Profile'),
            tiles: <SettingsTile>[
              SettingsTile.navigation(
                leading: const Icon(Icons.person),
                title: const Text('Edit Profile'),
                value: const Text('John Doe'),
                onPressed: (BuildContext context) {
                  // Navigate to edit profile page
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.email),
                title: const Text('Email'),
                value: const Text('johndoe@example.com'),
                onPressed: (BuildContext context) {
                  // Navigate to change email page
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.phone),
                title: const Text('Phone'),
                value: const Text('+1 234 567 8900'),
                onPressed: (BuildContext context) {
                  // Navigate to change phone number page
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Security'),
            tiles: <SettingsTile>[
              SettingsTile.navigation(
                leading: const Icon(Icons.lock),
                title: const Text('Change Password'),
                onPressed: (BuildContext context) {
                  // Navigate to change password page
                },
              ),
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() {
                    _biometricsEnabled = value;
                  });
                },
                initialValue: _biometricsEnabled,
                leading: const Icon(Icons.fingerprint),
                title: const Text('Enable Biometrics'),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Notifications'),
            tiles: <SettingsTile>[
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                },
                initialValue: _notificationsEnabled,
                leading: const Icon(Icons.notifications),
                title: const Text('Push Notifications'),
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.email),
                title: const Text('Email Notifications'),
                onPressed: (BuildContext context) {
                  // Navigate to email notification settings
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Privacy'),
            tiles: <SettingsTile>[
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() {
                    _locationEnabled = value;
                  });
                },
                initialValue: _locationEnabled,
                leading: const Icon(Icons.location_on),
                title: const Text('Location Services'),
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.delete),
                title: const Text('Delete Account'),
                onPressed: (BuildContext context) {
                  // Show delete account confirmation dialog
                },
              ),
            ],
          ),
          SettingsSection(
            title: const Text('Preferences'),
            tiles: <SettingsTile>[
              SettingsTile.navigation(
                leading: const Icon(Icons.language),
                title: const Text('Language'),
                value: const Text('English'),
                onPressed: (BuildContext context) {
                  // Navigate to language selection page
                },
              ),
              SettingsTile.switchTile(
                onToggle: (value) {
                  setState(() {
                    _customThemeEnabled = value;
                  });
                },
                initialValue: _customThemeEnabled,
                leading: const Icon(Icons.format_paint),
                title: const Text('Enable custom theme'),
              ),
            ],
          ),
          SettingsSection(
            title: const Text('About'),
            tiles: <SettingsTile>[
              SettingsTile.navigation(
                leading: const Icon(Icons.info),
                title: const Text('App Version'),
                value: const Text('1.0.0'),
                onPressed: (BuildContext context) {
                  // Show app version details
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.description),
                title: const Text('Terms of Service'),
                onPressed: (BuildContext context) {
                  // Navigate to Terms of Service page
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.privacy_tip),
                title: const Text('Privacy Policy'),
                onPressed: (BuildContext context) {
                  // Navigate to Privacy Policy page
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
