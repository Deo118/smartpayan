import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:smartpayan/main.dart';

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
  bool verifying = false;

  void saveDevice() {  // Renamed from Future<void> to void, and removed async since no save here
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String deviceName = deviceNameController.text.trim();
    String mac = macController.text.trim().toUpperCase();

    if (deviceName.isEmpty || mac.isEmpty) {
      setState(() {
        errorMessage = "Please fill in all fields.";
        loading = false;
      });
      return;
    }

    // Check if device already exists (optional, but keep for UX)
    // Note: We can't check Firestore here since we're not saving yet. You could add a pre-check if needed.

    setState(() {
      loading = false;
      verifying = true;
    });

    verifyMac(deviceName, mac);  // Pass deviceName and mac to verifyMac
  }

  void verifyMac(String deviceName, String mac) {
    DatabaseReference ref = FirebaseDatabase.instance.ref('devices/$mac/sensorData/macAddress');  // Fixed path: sensorData/macAddress
    bool verified = false;
    StreamSubscription? subscription;

    subscription = ref.onValue.listen((event) {
      String rtDbMac = event.snapshot.value as String? ?? '';
      if (rtDbMac == mac) {
        verified = true;
        subscription?.cancel();

        // Success: Now save to Firestore and navigate
        _saveToFirestoreAndNavigate(deviceName, mac);
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (!verified) {
        subscription?.cancel();
        setState(() {
          verifying = false;
          errorMessage = "MAC verification failed. Ensure ESP32 is online and sending data.";
        });
      }
    });
  }

  Future<void> _saveToFirestoreAndNavigate(String deviceName, String mac) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userDocId)
          .collection("deviceInfo")
          .doc(mac)
          .set({
            'name': deviceName,
            'mac': mac,
            'createdAt': FieldValue.serverTimestamp(),
          });

      // Navigate to HomeScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userDocId: widget.userDocId,
            deviceId: mac,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        verifying = false;
        errorMessage = "Error saving device: $e";
      });
    }
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
              decoration: _inputStyle("Device MAC Address (e.g., AA:BB:CC:DD:EE:FF)"),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            if (verifying)
              const Text("Verifying MAC with ESP32...", style: TextStyle(color: Colors.yellow)),
            if (errorMessage.isNotEmpty)
              Text(errorMessage, style: const TextStyle(color: Colors.redAccent)),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: (loading || verifying) ? null : saveDevice,
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