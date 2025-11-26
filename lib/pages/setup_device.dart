import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:smartpayan/main.dart';
import '../widgets/back_button.dart';

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

  void saveDevice() {
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

    setState(() {
      loading = false;
      verifying = true;
    });

    verifyMac(deviceName, mac);
  }

  void verifyMac(String deviceName, String mac) {
    DatabaseReference ref =
        FirebaseDatabase.instance.ref('devices/$mac/sensorData/macAddress');
    bool verified = false;
    StreamSubscription? subscription;

    subscription = ref.onValue.listen((event) {
      String rtDbMac = event.snapshot.value as String? ?? '';
      if (rtDbMac == mac) {
        verified = true;
        subscription?.cancel();
        _saveToFirestoreAndNavigate(deviceName, mac);
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (!verified) {
        subscription?.cancel();
        setState(() {
          verifying = false;
          errorMessage =
              "MAC verification failed. Ensure ESP32 is online and sending data.";
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
                    "Setup Device",
                    style: TextStyle(
                      fontSize: 28,
                      color: Color(0xFF1e1d50),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  TextField(
                    controller: deviceNameController,
                    decoration: _inputStyle("Device Name"),
                    style: const TextStyle(color: Color(0xFF1e1d50)),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: macController,
                    decoration: _inputStyle(
                        "Device MAC Address (e.g., AA:BB:CC:DD:EE:FF)"),
                    style: const TextStyle(color: Color(0xFF1e1d50)),
                  ),
                  const SizedBox(height: 16),

                  if (verifying)
                    const Text(
                      "Verifying MAC with ESP32...",
                      style: TextStyle(color: Color(0xFF1e1d50)),
                    ),
                  if (errorMessage.isNotEmpty)
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: (loading || verifying) ? null : saveDevice,
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
                            "Save & Connect",
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
