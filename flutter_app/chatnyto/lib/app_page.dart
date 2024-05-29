import 'package:flutter/material.dart';
import 'bottom_nav_bar.dart';
import 'notifications_page/notifications_page.dart';
import 'connection_page/connection_page.dart';
import 'chat_page/chat_page.dart';

class AppPage extends StatefulWidget {
  const AppPage({super.key});

  @override
  State<AppPage> createState() => _AppPageState();
}

class _AppPageState extends State<AppPage> {
  int _currentIndex = 0;
  final PageController _pageController = PageController(initialPage: 0);
  String _brokerIP = '127.0.0.1'; // Initial broker IP

  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      ChatPage(brokerIP: _brokerIP),
      const NotificationsPage(),
      ConnectionPage(
        updateBrokerIP: updateBrokerIP,
        brokerIP: _brokerIP,
      ),
    ];
  }

  void updateBrokerIP(String newBrokerIP) {
    setState(() {
      _brokerIP = newBrokerIP;
      pages[0] = ChatPage(brokerIP: _brokerIP);
      pages[2] =
          ConnectionPage(updateBrokerIP: updateBrokerIP, brokerIP: _brokerIP);
    });
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
