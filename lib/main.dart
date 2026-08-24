import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const SttArenaApp());
}

class SttArenaApp extends StatelessWidget {
  const SttArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STT Arena',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
