import 'package:flutter/material.dart';
import 'constants/app_colors.dart';
import 'screens/auth/splash_screen.dart';

void main() {
  runApp(const ProPortApp());
}

class ProPortApp extends StatelessWidget {
  const ProPortApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProPort',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.input,
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}