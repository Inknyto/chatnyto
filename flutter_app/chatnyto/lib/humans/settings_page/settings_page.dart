import 'package:flutter/material.dart';

import '../../core/settings/entity_settings.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const EntitySettings(title: 'Parameters — Humans');
  }
}
