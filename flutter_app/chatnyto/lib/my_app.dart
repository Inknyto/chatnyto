import 'package:flutter/material.dart';
import 'app_page.dart';

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

ThemeData myTheme = ThemeData(
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: Colors.white),
  ),
);
