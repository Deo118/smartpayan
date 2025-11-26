import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/back_button.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool loading = false;
  String errorMessage = "";

  Future<void> createAccount() async {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String username = usernameController.text.trim();
    String password = passwordController.text.trim();
    String confirmPassword = confirmPasswordController.text.trim();

    if (username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      setState(() {
        errorMessage = "Please fill in all fields.";
        loading = false;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        errorMessage = "Passwords do not match.";
        loading = false;
      });
      return;
    }

    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    if (existing.docs.isNotEmpty) {
      setState(() {
        errorMessage = "Username already exists. Choose another.";
        loading = false;
      });
      return;
    }

    await FirebaseFirestore.instance.collection('users').add({
      'username': username,
      'password': password,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() => loading = false);

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Centered Form
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Create Account",
                    style: TextStyle(
                      fontSize: 28,
                      color: Color(0xFF1e1d50),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

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

                  TextField(
                    controller: confirmPasswordController,
                    decoration: _inputStyle("Confirm Password"),
                    style: const TextStyle(color: Color(0xFF1e1d50)),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),

                  if (errorMessage.isNotEmpty)
                    Text(errorMessage,
                        style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: loading ? null : createAccount,
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
                        : const Text(
                            "Create Account",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Overlayed Back Button
          const BackButtonWidget(),
        ],
      ),
    );
  }

  InputDecoration _inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF1e1d50)),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Color(0xFF1e1d50)),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.blueAccent),
      ),
    );
  }
}
