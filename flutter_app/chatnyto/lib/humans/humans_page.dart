import 'package:flutter/material.dart';
import 'bottom_nav_bar.dart';
import 'notifications_page/notifications_page.dart';
import 'settings_page/settings_page.dart';
import 'connections_page/connections_page.dart';
import 'chat_page/chat_page.dart';
import 'heat_map_page/heat_map_page.dart';

class HumansPage extends StatefulWidget {
  const HumansPage({super.key});

  @override
  State<HumansPage> createState() => _HumansPageState();
}

class _HumansPageState extends State<HumansPage> {
  int _currentIndex = 0;
  final PageController _pageController = PageController(initialPage: 0);
  String _brokerIP = '127.0.0.1'; // Initial broker IP
  String _deviceIP = '127.0.0.1'; // Initial broker IP
  String _topicName = 'chat'; // Initial broker IP

  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      ChatPage(
        brokerIP: _brokerIP,
        topicName: _topicName,
        deviceIP: _deviceIP,
      ),
      // const NotificationsPage(),
      const ConnectionsPage(),
      const HeatMapPage(),
      SettingsPage(),
    ];
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        children: pages,
        onPageChanged: (int index) => setState(() => _currentIndex = index),
      ),
      bottomNavigationBar: BottomNavigationBarWidget(
        currentIndex: _currentIndex,
        pageController: _pageController,
        onTabTapped: (int index) {
          setState(() {
            _currentIndex = index;
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 500),
              curve: Curves.ease,
            );
          });
        },
      ),
      backgroundColor: const Color(0xFF1B1926),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
