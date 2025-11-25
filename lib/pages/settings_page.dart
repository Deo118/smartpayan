import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatelessWidget {
  final String userDocId;
  final String deviceId; // or MAC address

  const SettingsPage({super.key, required this.userDocId, required this.deviceId});

  Future<void> deleteDevice(BuildContext context) async {
    try {
      // Delete the device document from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('deviceInfo')
          .doc(deviceId)
          .delete();

      // Show a confirmation message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device deleted successfully.")),
      );

      // Navigate back to login page
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error deleting device: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          // Show confirmation dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Delete Device"),
              content: const Text(
                  "Are you sure you want to delete this device? This action cannot be undone."),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(); // cancel
                  },
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(); // close dialog
                    deleteDevice(context);
                  },
                  child: const Text("Delete"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                ),
              ],
            ),
          );
        },
        child: const Text("Delete Device"),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.red),
      ),
    );
  }
}
