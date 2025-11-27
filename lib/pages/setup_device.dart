import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../widgets/back_button.dart';
import '../main.dart';

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
  bool verifying = false;
  String errorMessage = "";

  // SAVE BUTTON
  void saveDevice() {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String name = deviceNameController.text.trim();
    String macRaw = macController.text.trim().toUpperCase();

    if (name.isEmpty || macRaw.isEmpty) {
      setState(() {
        loading = false;
        errorMessage = "Please fill in all fields.";
      });
      return;
    }

    setState(() {
      loading = false;
      verifying = true;
    });

    verifyMac(name, macRaw);
  }

  // MAC VERIFICATION
  void verifyMac(String deviceName, String macRaw) {
    String safeMac = macRaw.replaceAll(":", "_");

    DatabaseReference ref = FirebaseDatabase.instance
        .ref("devices/$safeMac/sensorData/macAddress");

    bool verified = false;
    StreamSubscription? sub;

    sub = ref.onValue.listen((event) {
      try {
        final val = event.snapshot.value;

        if (val == null) return; // no data yet

        String rtdbMac = val.toString().toUpperCase();

        // ⭐ RAW MAC comparison (correct)
        if (rtdbMac == macRaw) {
          verified = true;
          sub?.cancel();
          _saveAndNavigate(deviceName, safeMac);
        }
      } catch (e) {
        debugPrint("Verification error: $e");
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (!verified) {
        sub?.cancel();
        setState(() {
          verifying = false;
          errorMessage = "MAC verification failed. ESP32 not sending data.";
        });
      }
    });
  }

  // SAVE TO FIRESTORE + NAVIGATE
  Future<void> _saveAndNavigate(String name, String safeMac) async {
    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userDocId)
          .collection("deviceInfo")
          .doc(safeMac)
          .set({
        "name": name,
        "mac": safeMac,
        "createdAt": FieldValue.serverTimestamp(),
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            userDocId: widget.userDocId,
            deviceId: safeMac,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        verifying = false;
        errorMessage = "Failed to save device: $e";
      });
    }
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
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
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1e1d50),
                    ),
                  ),
                  const SizedBox(height: 30),

                  TextField(
                    controller: deviceNameController,
                    decoration: _style("Device Name"),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: macController,
                    decoration: _style("Device MAC (AA:BB:CC:DD:EE:FF)"),
                  ),
                  const SizedBox(height: 16),

                  if (verifying)
                    const Text("Verifying MAC with ESP32...",
                        style: TextStyle(color: Colors.black87)),

                  if (errorMessage.isNotEmpty)
                    Text(errorMessage,
                        style: const TextStyle(color: Colors.red)),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: (loading || verifying) ? null : saveDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e1d50),
                    ),
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Save & Connect",
                            style: TextStyle(
                                color: Colors.white, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),

          const BackButtonWidget(),
        ],
      ),
    );
  }

  InputDecoration _style(String label) {
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
