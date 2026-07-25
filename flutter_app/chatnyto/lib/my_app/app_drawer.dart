import 'package:flutter/material.dart';

import '../account/account_page.dart';
import '../account/security_page.dart';
import '../ais/ais_page.dart';
import '../core/brokers/brokers_page.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/liquid_glass.dart';
import '../humans/humans_page.dart';
import '../robots/robots_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: Colors.transparent,
      child: GlassBackground(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Text('ChatNyto',
                    style: TextStyle(color: Colors.white, fontSize: 26)),
              ),
            ),
            _item(context, Icons.people_alt_rounded, 'Humans',
                const HumansPage()),
            _item(context, Icons.smart_toy_rounded, 'Robots',
                const RobotsPage()),
            _item(context, Icons.auto_awesome_rounded, 'AIs', const AIsPage()),
            const Divider(),
            _item(context, Icons.dns_rounded, 'Brokers', const BrokersPage()),
            _item(context, Icons.shield_rounded, 'Security & Identity',
                const SecurityPage()),
            _item(context, Icons.manage_accounts_rounded, 'Account',
                const AccountPage()),
            const Divider(),
            ListTile(
              leading: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              title: const Text('Dark / light mode'),
              onTap: ThemeController.instance.toggle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
      BuildContext context, IconData icon, String title, Widget page) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, GlassPageRoute(page: page));
      },
    );
  }
}
