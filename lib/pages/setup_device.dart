import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
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

  final RegExp macRegex = RegExp(r'^[A-F0-9]{2}(:[A-F0-9]{2}){5}$');
  static const int nameMaxLength = 20;

  @override
  void dispose() {
    deviceNameController.dispose();
    macController.dispose();
    super.dispose();
  }

  void saveDevice() {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    final name = deviceNameController.text.trim();
    final macRaw = macController.text.trim().toUpperCase();

    if (name.isEmpty || macRaw.isEmpty) {
      setState(() {
        loading = false;
        errorMessage = "Please fill in all fields.";
      });
      return;
    }

    if (name.length > nameMaxLength) {
      setState(() {
        loading = false;
        errorMessage = "Device name must be $nameMaxLength characters or fewer.";
      });
      return;
    }

    if (!macRegex.hasMatch(macRaw)) {
      setState(() {
        loading = false;
        errorMessage = "Invalid MAC format. Use AA:BB:CC:DD:EE:FF.";
      });
      return;
    }

    setState(() {
      loading = false;
      verifying = true;
    });

    verifyMac(name, macRaw);
  }

  // verify MAC with RTDB
  void verifyMac(String deviceName, String macRaw) {
    final safeMac = macRaw.replaceAll(":", "_");
    final ref = FirebaseDatabase.instance.ref("devices/$safeMac/sensorData/macAddress");

    bool verified = false;
    StreamSubscription? sub;

    sub = ref.onValue.listen((event) async {
      final val = event.snapshot.value;
      if (val == null) return;

      if (val.toString().toUpperCase() == macRaw) {
        verified = true;
        await sub?.cancel();
        checkDeviceOwner(deviceName, safeMac, macRaw);
      }
    });

    Future.delayed(const Duration(seconds: 30), () async {
      if (!verified) {
        await sub?.cancel();
        if (mounted) {
          setState(() {
            verifying = false;
            errorMessage = "MAC verification failed. ESP32 not broadcasting.";
          });
        }
      }
    });
  }

  // check if device already has an owner
  Future<void> checkDeviceOwner(String name, String safeMac, String macRaw) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("deviceOwners")
          .doc(safeMac)
          .get();

      if (doc.exists) {
        final owner = doc["userId"];
        if (owner != widget.userDocId) {
          setState(() {
            verifying = false;
            errorMessage = "This device is already registered to another user.";
          });
          return;
        }
      }

      // If owner does not exist OR owner is same user → continue
      _saveAndNavigate(name, safeMac, macRaw);

    } catch (e) {
      setState(() {
        verifying = false;
        errorMessage = "Error verifying device owner: $e";
      });
    }
  }

  // save ownership, deviceInfo, Supabase, cache
  Future<void> _saveAndNavigate(String name, String safeMac, String macRaw) async {
    try {
      // Save under user
      await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userDocId)
          .collection("deviceInfo")
          .doc(safeMac)
          .set({
        "name": name,
        "mac": safeMac,
        "mac_original": macRaw,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Save owner
      await FirebaseFirestore.instance
          .collection("deviceOwners")
          .doc(safeMac)
          .set({
        "userId": widget.userDocId,
        "deviceId": safeMac,
        "mac_original": macRaw,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Supabase
      await Supabase.instance.client.from("devices").upsert({
        "device_id": safeMac,
        "mac_address": macRaw,
        "name": name,
      });

      // Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("device_name_$safeMac", name);
      await prefs.setString("device_mac_$safeMac", macRaw);
      await prefs.setString("deviceId", safeMac);

      // Navigate to home
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            userDocId: widget.userDocId,
            deviceId: safeMac,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      setState(() {
        verifying = false;
        errorMessage = "Failed to save device: $e";
      });
    }
  }

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
                    maxLength: nameMaxLength,
                    decoration: _style("Device Name"),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: macController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _style("Device MAC (AA:BB:CC:DD:EE:FF)"),
                  ),
                  const SizedBox(height: 16),

                  if (verifying)
                    const Text("Verifying MAC with ESP32...",
                        style: TextStyle(color: Colors.black87)),

                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(errorMessage, style: const TextStyle(color: Colors.red)),
                    ),

                  const SizedBox(height: 20),

                  ElevatedButton(
                    onPressed: (loading || verifying) ? null : saveDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1e1d50),
                    ),
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Save & Connect",
                            style: TextStyle(color: Colors.white, fontSize: 18)),
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
      counterText: "",
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
