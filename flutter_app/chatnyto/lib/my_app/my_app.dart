import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/liquid_glass.dart';
import 'app_drawer.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'ChatNyto',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          // Required by the quill editor/toolbar widgets; without it they
          // throw and blank the whole page.
          localizationsDelegates: FlutterQuillLocalizations.localizationsDelegates,
          home: const AppPage(),
        );
      },
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('ChatNyto'),
          actions: [
            IconButton(
              tooltip: 'Toggle dark/light mode',
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
              ),
              onPressed: ThemeController.instance.toggle,
            ),
          ],
        ),
        drawer: const AppDrawer(),
        body: const AppContent(),
      ),
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
            'Bienvenue sur ChatNyto!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cette application de chat permet de discuter avec humains, '
            'robots et intelligences artificielles, avec ou sans internet '
            '(MQTT sur LoRa). Ouvrez le menu pour accéder aux catégories.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            Icons.people_alt_rounded,
            'Humains',
            'Discussions classiques, chiffrées de bout en bout',
          ),
          _buildSection(
            context,
            Icons.smart_toy_rounded,
            'Robots',
            'Discutez avec les objets connectés',
          ),
          _buildSection(
            context,
            Icons.auto_awesome_rounded,
            'IAs',
            'Intelligences artificielles locales et cloud',
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
      BuildContext context, IconData icon, String title, String description) {
    return LiquidGlass(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        subtitle: Text(description, style: const TextStyle(fontSize: 15)),
      ),
    );
  }
}
