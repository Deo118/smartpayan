import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/services.dart';

class SettingsPage extends StatefulWidget {
  final String userDocId;
  final String deviceId; // ALWAYS SAFE MAC (underscores)

  const SettingsPage({
    super.key,
    required this.userDocId,
    required this.deviceId,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool editingName = false;
  bool savingName = false;

  String deviceName = "";
  String macAddress = ""; // DISPLAY ONLY -> colon format
  final TextEditingController nameController = TextEditingController();

  static const int nameMaxLength = 20;

  @override
  void initState() {
    super.initState();
    loadDeviceInfo();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  // SharedPreferences keys
  String _prefNameKey(String id) => "device_name_$id";
  String _prefMacKey(String id) => "device_mac_$id";

  Future<void> loadDeviceInfo() async {
    final safeMac = widget.deviceId;
    final prefs = await SharedPreferences.getInstance();

    // 1) Try cached values
    final cachedName = prefs.getString(_prefNameKey(safeMac));
    final cachedMac = prefs.getString(_prefMacKey(safeMac));

    if (cachedName != null || cachedMac != null) {
      setState(() {
        deviceName = cachedName ?? "Device";
        macAddress = cachedMac ?? safeMac.replaceAll("_", ":");
        nameController.text = deviceName;
      });

      _refreshFromRemote(safeMac, prefs);
      return;
    }

    // 2) Firestore
    String? fsName;
    String? fsOriginalMac;

    final fs = await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.userDocId)
        .collection("deviceInfo")
        .doc(safeMac)
        .get();

    if (fs.exists) {
      fsName = fs["name"];
      fsOriginalMac = fs["mac_original"]; // may not exist for older devices
    }

    // 3) RTDB macAddress
    String? rtdbMac;
    try {
      final macSnap = await FirebaseDatabase.instance
          .ref("devices/$safeMac/sensorData/macAddress")
          .get();
      if (macSnap.exists) {
        rtdbMac = macSnap.value.toString();
      }
    } catch (_) {}

    final displayMac = rtdbMac ?? fsOriginalMac ?? safeMac.replaceAll("_", ":");

    setState(() {
      deviceName = fsName ?? "Device";
      macAddress = displayMac;
      nameController.text = deviceName;
    });

    // Cache
    await prefs.setString(_prefNameKey(safeMac), deviceName);
    await prefs.setString(_prefMacKey(safeMac), displayMac);
  }

  Future<void> _refreshFromRemote(String safeMac, SharedPreferences prefs) async {
    try {
      final fs = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userDocId)
          .collection("deviceInfo")
          .doc(safeMac)
          .get();

      String? fsName = fs["name"];
      String? fsOriginal = fs["mac_original"];

      String? rtdbMac;
      final snap = await FirebaseDatabase.instance
          .ref("devices/$safeMac/sensorData/macAddress")
          .get();
      if (snap.exists) rtdbMac = snap.value.toString();

      final displayMac = rtdbMac ?? fsOriginal ?? safeMac.replaceAll("_", ":");

      if (!mounted) return;

      setState(() {
        deviceName = fsName ?? deviceName;
        macAddress = displayMac;
      });

      await prefs.setString(_prefNameKey(safeMac), deviceName);
      await prefs.setString(_prefMacKey(safeMac), displayMac);
    } catch (_) {}
  }

  Future<void> saveDeviceName() async {
    final newName = nameController.text.trim();

    if (newName.isEmpty || newName == deviceName) {
      setState(() => editingName = false);
      return;
    }

    if (newName.length > nameMaxLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Name must be $nameMaxLength characters or fewer")),
      );
      return;
    }

    setState(() => savingName = true);

    final safeMac = widget.deviceId;

    try {
      await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userDocId)
          .collection("deviceInfo")
          .doc(safeMac)
          .update({"name": newName});

      await Supabase.instance.client
          .from("devices")
          .update({"name": newName})
          .eq("device_id", safeMac);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefNameKey(safeMac), newName);

      setState(() {
        deviceName = newName;
        editingName = false;
        savingName = false;
      });
    } catch (e) {
      savingName = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error saving name: $e")),
      );
    }
  }

  Future<void> deleteDevice() async {
  final safeMac = widget.deviceId;

  try {
    // Delete user-specific deviceInfo
    await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.userDocId)
        .collection("deviceInfo")
        .doc(safeMac)
        .delete();

    // Delete global device owner to free the ESP32 for another user
    await FirebaseFirestore.instance
        .collection("deviceOwners")
        .doc(safeMac)
        .delete();

    // Delete Supabase rows
    await Supabase.instance.client.from("device_tokens").delete().eq("device_id", safeMac);
    await Supabase.instance.client.from("notifications").delete().eq("device_id", safeMac);
    await Supabase.instance.client.from("devices").delete().eq("device_id", safeMac);

    // Delete RTDB node
    await FirebaseDatabase.instance.ref("devices/$safeMac").remove();

    // Clear local cache
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefNameKey(safeMac));
    await prefs.remove(_prefMacKey(safeMac));
    await prefs.remove('deviceId');

    // Return to login
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error deleting device: $e")),
    );
  }
}

  void confirmDeleteDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete Device"),
        content: Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Delete"),
            onPressed: () {
              Navigator.pop(ctx);
              deleteDevice();
            },
          ),
        ],
      ),
    );
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Device Information",
                style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),

            // GLASS CARD (UI UNTOUCHED)
            _buildInfoCard(),

            SizedBox(height: 50),
            Center(
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: confirmDeleteDialog,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Colors.red),
                    child: Text("Delete Device"),
                  ),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: logout,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Color(0xFF1e1d50)),
                    child: Text("Logout"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Device Name", style: TextStyle(color: Colors.white70)),
          SizedBox(height: 6),

          Row(
            children: [
              Expanded(
                child: editingName
                    ? TextField(
                        controller: nameController,
                        style: TextStyle(color: Colors.white, fontSize: 20),
                        decoration: InputDecoration(
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white)),
                        ),
                      )
                    : Text(deviceName,
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: Icon(editingName ? Icons.close : Icons.edit, color: Colors.white),
                onPressed: () {
                  setState(() {
                    editingName = !editingName;
                    nameController.text = deviceName;
                  });
                },
              ),
            ],
          ),

          if (editingName)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Center(
                child: ElevatedButton(
                  onPressed: savingName ? null : saveDeviceName,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, foregroundColor: Colors.black),
                  child: savingName
                      ? CircularProgressIndicator(color: Colors.black)
                      : Text("Save Name"),
                ),
              ),
            ),

          SizedBox(height: 20),
          Text("Mac Address", style: TextStyle(color: Colors.white70)),
          SizedBox(height: 6),

          Row(
            children: [
              Expanded(
                  child: Text(macAddress,
                      style: TextStyle(color: Colors.white, fontSize: 16))),
              IconButton(
                icon: Icon(Icons.copy, color: Colors.white70, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: macAddress));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text("MAC Address copied")));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
