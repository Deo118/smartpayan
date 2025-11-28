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
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    String? userDocId = prefs.getString('userDocId');
    String? deviceId = prefs.getString('deviceId');

    // Simulate loading delay (keep or adjust)
    await Future.delayed(const Duration(seconds: 3));

    if (isLoggedIn && userDocId != null && deviceId != null) {
      // User is logged in and has a device: Go to dashboard
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(userDocId: userDocId, deviceId: deviceId),
        ),
      );
    } else {
      // Not logged in: Go to login
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF1e1d50)),
      ),
    );
  }
}