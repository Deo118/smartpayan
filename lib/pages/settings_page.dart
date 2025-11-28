import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';  

class SettingsPage extends StatelessWidget {
  final String userDocId;
  final String deviceId;

  const SettingsPage({super.key, required this.userDocId, required this.deviceId});

  Future<void> deleteDevice(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('deviceInfo')
          .doc(deviceId)
          .delete();

      // Clear shared preferences to force re-login
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device deleted successfully.")),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting device: $e")),
      );
    }
  }

  Future<void> logout(BuildContext context) async {
    // Clear shared preferences to force re-login
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Delete Device"),
                  content: const Text("Are you sure you want to delete this device?"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        deleteDevice(context);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text("Delete"),
                    ),
                  ],
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.red,
            ),
            child: const Text("Delete Device"),
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () => logout(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF1e1d50),
            ),
            child: const Text("Logout"),
          ),
        ],
      ),
    );
  }
}