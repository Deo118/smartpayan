import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool loading = false;
  String errorMessage = "";

  Future<void> loginUser() async {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String username = usernameController.text.trim();
    String password = passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = "Please fill in all fields.";
        loading = false;
      });
      return;
    }

    // Query Firestore for username & password
    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .where('password', isEqualTo: password)
        .get();

    if (result.docs.isNotEmpty) {
      // SUCCESS → Go to setup_device page with username as argument
      Navigator.pushReplacementNamed(
        context,
        '/setup-device',
        arguments: username,
      );
    } else {
      setState(() => errorMessage = "Invalid username or password.");
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
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
              controller: usernameController,
              decoration: _inputStyle("Username"),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: passwordController,
              decoration: _inputStyle("Password"),
              style: const TextStyle(color: Colors.white),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            if (errorMessage.isNotEmpty)
              Text(errorMessage,
                  style: const TextStyle(color: Colors.redAccent)),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: loading ? null : loginUser,
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Login"),
            ),

            const SizedBox(height: 12),

            TextButton(
              onPressed: () {
                // Only navigate to Create Account page
                Navigator.pushNamed(context, '/create-account');
              },
              child: const Text(
                "Don't have an account? Create Account",
                style: TextStyle(color: Colors.white70),
              ),
            ),
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
