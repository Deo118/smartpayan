import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController macController = TextEditingController();

  bool loading = false;
  String errorMessage = "";

  Future<void> loginDevice() async {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String name = nameController.text.trim();
    String mac = macController.text.trim();

    // Query Firestore
    final result = await FirebaseFirestore.instance
        .collection('devices')
        .where('name', isEqualTo: name)
        .where('mac', isEqualTo: mac)
        .get();

    if (result.docs.isNotEmpty) {
      // SUCCESS → Go to dashboard
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() => errorMessage = "Device not found. Check inputs.");
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white.withOpacity(0.85),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "SmartPayan Login",
              style: TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: nameController,
              decoration: _inputStyle("Device Name"),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: macController,
              decoration: _inputStyle("Device MAC Address"),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            if (errorMessage.isNotEmpty)
              Text(errorMessage,
                  style: const TextStyle(color: Colors.redAccent)),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: loading ? null : loginDevice,
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Save & Connect"),
            )
          ],
        ),
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.white38),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.greenAccent),
      ),
    );
  }
}
