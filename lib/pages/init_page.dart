import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayan/main.dart';

class InitializationPage extends StatefulWidget {
  const InitializationPage({super.key});

  @override
  State<InitializationPage> createState() => _InitializationPageState();
}

class _InitializationPageState extends State<InitializationPage> {
  bool _navigated = false; // Prevent double navigation

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final String? userDocId = prefs.getString('userDocId');
    final String? rawDeviceId = prefs.getString('deviceId');

    // Sanitize device ID (ensure match with ESP32 + Supabase)
    final String? deviceId =
        rawDeviceId?.replaceAll(":", "_").trim().isNotEmpty == true
            ? rawDeviceId!.replaceAll(":", "_")
            : null;

    // Add short delay for splash animation / background initialization
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted || _navigated) return;

    if (isLoggedIn && userDocId != null && deviceId != null) {
      _navigated = true;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              HomeScreen(userDocId: userDocId, deviceId: deviceId),
        ),
      );
    } else {
      // No credentials → go to login
      _navigated = true;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF1e1d50),
        ),
      ),
    );
  }
}
