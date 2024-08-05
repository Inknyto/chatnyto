import 'package:flutter/material.dart';
import 'app_drawer.dart';


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: const AppPage(),
      theme: myTheme,
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My App'),
      ),
      drawer: const AppDrawer(),
      body: const AppContent(),
    );
  }
}


class AppContent extends StatelessWidget {
  const AppContent({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bienvenue sur Chat Nyto!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cette application de chat permet de discuter avec humains, robots et intelliences artificielles. '
            'Vous pouvez accéder aux catégories en cliquant sur le menu de navigation',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          _buildSectionDescription(
            'Humains',
            'Cette section consiste en une application de discussion classique',
          ),
          _buildSectionDescription(
            'Robots',
            'Cette section permet de discuter avec les objets connectés',
          ),
          _buildSectionDescription(
            'IAs',
            'Cette section eprmet de discuter avec des intelligences artificielles en local, et dans le cloud',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDescription(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

ThemeData myTheme = ThemeData(
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.black),
  ),
  scaffoldBackgroundColor: Colors.white,
);
