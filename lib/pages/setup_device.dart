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

  // MAC pattern: AA:BB:CC:DD:EE:FF (hex uppercase)
  final RegExp macRegex = RegExp(r'^[A-F0-9]{2}(:[A-F0-9]{2}){5}$');
  static const int nameMaxLength = 20;

  @override
  void dispose() {
    deviceNameController.dispose();
    macController.dispose();
    super.dispose();
  }

  // CHECK IF DEVICE IS ALREADY OWNED BY ANOTHER USER
  Future<bool> deviceAlreadyOwned(String safeMac) async {
    final doc = await FirebaseFirestore.instance
        .collection("deviceOwners")
        .doc(safeMac)
        .get();

    if (!doc.exists) return false; // nobody owns it yet

    final ownerId = doc.data()?["ownerId"];
    if (ownerId == widget.userDocId) return false; // same user → allow

    return true; // owned by someone else
  }

  // ---------------------------------------------------------------------------

  void saveDevice() {
    setState(() {
      loading = true;
      errorMessage = "";
    });

    String name = deviceNameController.text.trim();
    String macRaw = macController.text.trim().toUpperCase();

    // Basic validation
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
        errorMessage = "Invalid MAC format. Use AA:BB:CC:DD:EE:FF (hex + colons).";
      });
      return;
    }

    final safeMac = macRaw.replaceAll(":", "_");

    // Prevent duplicate device registration across accounts
    deviceAlreadyOwned(safeMac).then((owned) {
      if (owned) {
        setState(() {
          loading = false;
          verifying = false;
          errorMessage =
              "This ESP32 is already registered to another SmartPayan account.";
        });
        return;
      }

      // If not owned → proceed with normal MAC verification
      setState(() {
        loading = false;
        verifying = true;
      });

      verifyMac(name, macRaw);
    });
  }

  // ---------------------------------------------------------------------------

  void verifyMac(String deviceName, String macRaw) {
    final String safeMac = macRaw.replaceAll(":", "_");
    final DatabaseReference ref =
        FirebaseDatabase.instance.ref("devices/$safeMac/sensorData/macAddress");

    bool verified = false;
    StreamSubscription<DatabaseEvent>? sub;

    sub = ref.onValue.listen((event) {
      try {
        final val = event.snapshot.value;
        if (val == null) return;

        String rtdbMac = val.toString().toUpperCase();

        if (rtdbMac == macRaw) {
          verified = true;
          sub?.cancel();
          _saveAndNavigate(deviceName, safeMac, macRaw);
        }
      } catch (e) {
        debugPrint("verifyMac listener error: $e");
      }
    }, onError: (e) {
      debugPrint("verifyMac subscription error: $e");
    });

    // Timeout after 30 sec
    Future.delayed(const Duration(seconds: 30), () {
      if (!verified) {
        sub?.cancel();
        if (mounted) {
          setState(() {
            verifying = false;
            errorMessage = "MAC verification failed. ESP32 not sending data.";
          });
        }
      }
    });
  }

  // ---------------------------------------------------------------------------

  Future<void> _saveAndNavigate(String name, String safeMac, String macRaw) async {
    try {
      // Save to Firestore inside user's collection
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

      // Save to Supabase (optional metadata, not ownership)
      await Supabase.instance.client.from("devices").upsert({
        "device_id": safeMac,
        "mac_address": macRaw,
        "name": name,
      });


      // REGISTER DEVICE OWNERSHIP GLOBALLY IN FIRESTORE
      await FirebaseFirestore.instance
          .collection("deviceOwners")
          .doc(safeMac)
          .set({
        "ownerId": widget.userDocId,
        "mac_original": macRaw,
        "createdAt": FieldValue.serverTimestamp(),
      });

      // Save locally
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name_$safeMac', name);
      await prefs.setString('device_mac_$safeMac', macRaw);
      await prefs.setString('deviceId', safeMac);

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
      if (mounted) {
        setState(() {
          verifying = false;
          errorMessage = "Failed to save device: $e";
        });
      }
    }
  }

  // ---------------------------------------------------------------------------

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
                    const Text(
                      "Verifying MAC with ESP32...",
                      style: TextStyle(color: Colors.black87),
                    ),

                  if (errorMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child:
                          Text(errorMessage, style: const TextStyle(color: Colors.red)),
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
