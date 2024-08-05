import 'package:flutter/material.dart';
import '../humans/humans_page.dart';
import '../robots/robots_page.dart';
import '../ais/ais_page.dart';
import '../account/account_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text('Categories', style: TextStyle(color: Colors.white, fontSize: 24)),
          ),
          _buildDrawerItem(context, 'Humans', const HumansPage()),
          _buildDrawerItem(context, 'Robots', const RobotsPage()),
          _buildDrawerItem(context, 'AIs', const AIsPage()),
          _buildDrawerItem(context, 'Account', const AccountPage()),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(BuildContext context, String title, Widget page) {
    return ListTile(
      title: Text(title),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (context) => page));
      },
    );
  }
}

