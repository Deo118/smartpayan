import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smartpayan/main.dart';
import 'package:smartpayan/pages/login_page.dart';

class SetupDevicePage extends StatefulWidget {
  final String userDocId;

  const SetupDevicePage({super.key, required this.userDocId});

  @override
  State<SetupDevicePage> createState() => _SetupDevicePageState();
}

class _SetupDevicePageState extends State<SetupDevicePage> {
  final TextEditingController deviceNameController = TextEditingController();
  final TextEditingController macController = TextEditingController();

  bool loading = false;
  String errorMessage = "";

  Future<void> saveDevice(String username) async {
  setState(() {
    loading = true;
    errorMessage = "";
  });

  String deviceName = deviceNameController.text.trim();
  String mac = macController.text.trim();

  if (deviceName.isEmpty || mac.isEmpty) {
    setState(() {
      errorMessage = "Please fill in all fields.";
      loading = false;
    });
    return;
  }

  // Check if device already exists for this user
  final existing = await FirebaseFirestore.instance
      .collection('users')
      .doc(widget.userDocId)
      .collection("deviceInfo")
      .where('mac', isEqualTo: mac)
      .get();

  if (existing.docs.isNotEmpty) {
    setState(() {
      errorMessage = "Device already registered.";
      loading = false;
    });
    return;
  }

  // Save device info AND get the new ID
  final doc = await FirebaseFirestore.instance
  .collection('users')
  .doc(widget.userDocId)
  .collection("deviceInfo")
  .add({
    'name': deviceName,
    'mac': mac,
    'createdAt': FieldValue.serverTimestamp(),
  });

  final String deviceId = doc.id; 

  setState(() => loading = false);

  // Navigate to home with deviceId
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (context) => HomeScreen(
        userDocId: widget.userDocId,
        deviceId: deviceId),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    // Get username passed from LoginPage

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Setup Device",
              style: TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: deviceNameController,
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
              onPressed: loading ? null : () => saveDevice(widget.userDocId),
              child: loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Save & Connect"),
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
