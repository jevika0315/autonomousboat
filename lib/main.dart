// ============================================================
// EV SQUARE - Camera Viewer App
// Company: EV SQUARE | Contact: +91-80722-80522
// ============================================================

import 'package:flutter/material.dart';
import 'screens/camera_screen.dart';

void main() {
  // Required for Flutter WebRTC to work correctly
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EVSquareApp());
}

class EVSquareApp extends StatelessWidget {
  const EVSquareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EV SQUARE Camera Viewer',
      debugShowCheckedModeBanner: false,   // Hides the red "DEBUG" banner
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A84FF),  // Electric Blue
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
      ),
      home: const CameraScreen(),
    );
  }
}
