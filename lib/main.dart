import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speech App',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        primaryColor: const Color(0xFF6366F1),
        scaffoldBackgroundColor: const Color(0xFFFAFBFC),
        cardColor: Colors.white,
        dividerColor: const Color(0xFFF3F4F6),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: Color(0xFF1A1A1A)),
          headlineMedium: TextStyle(color: Color(0xFF1A1A1A)),
          headlineSmall: TextStyle(color: Color(0xFF1A1A1A)),
          bodyLarge: TextStyle(color: Color(0xFF4A4A4A)),
          bodyMedium: TextStyle(color: Color(0xFF4A4A4A)),
          bodySmall: TextStyle(color: Color(0xFF6B7280)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
            elevation: 4,
            shadowColor: const Color(0xFF6366F1).withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAFBFC),
          foregroundColor: Color(0xFF1A1A1A),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData) {
            return HomeScreen();
          }

          return AuthScreen();
        },
      ),
    );
  }
}
