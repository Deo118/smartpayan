import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';  

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  late TapGestureRecognizer _createAccountTap;

  bool loading = false;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    _createAccountTap = TapGestureRecognizer()
      ..onTap = () {
        Navigator.pushNamed(context, '/create-account');
      };
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    _createAccountTap.dispose();
    super.dispose();
  }

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

    final result = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .where('password', isEqualTo: password)
        .get();

    if (result.docs.isNotEmpty) {
      final userDocId = result.docs.first.id;

      // Save login state to shared preferences for persistence
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userDocId', userDocId);

      Navigator.pushReplacementNamed(
        context,
        '/setup-device',
        arguments: userDocId,
      );
    } else {
      setState(() => errorMessage = "Invalid username or password.");
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "SmartPayan Login",
              style: TextStyle(
                fontSize: 28,
                color: Color(0xFF1e1d50),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 50),

            TextField(
              controller: usernameController,
              decoration: _inputStyle("Username"),
              style: const TextStyle(color: Color(0xFF1e1d50)),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: passwordController,
              decoration: _inputStyle("Password"),
              style: const TextStyle(color: Color(0xFF1e1d50)),
              obscureText: true,
            ),
            const SizedBox(height: 16),

            if (errorMessage.isNotEmpty)
              Text(
                errorMessage,
                style: const TextStyle(color: Colors.redAccent),
              ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: loading ? null : loginUser,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1e1d50),   
                foregroundColor: Colors.white,              
                padding: const EdgeInsets.symmetric(
                  horizontal: 50,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),  
                ),
              ),
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Login", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),

            RichText(
              text: TextSpan(
                text: "Don't have an account? ",
                style: const TextStyle(
                  color: Color(0xFF1e1d50),
                  fontSize: 14,
                ),
                children: [
                  TextSpan(
                    text: "Create Account",
                    style: const TextStyle(
                      color: Color(0xFF007BFF),
                      fontWeight: FontWeight.bold,
                    ),
                    recognizer: _createAccountTap,
                  ),
                ],
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
      labelStyle: const TextStyle(color: Color(0xFF1e1d50)),
      enabledBorder: UnderlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF1e1d50)),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: const BorderSide(color: Colors.blueAccent),
      ),
    );
  }
}