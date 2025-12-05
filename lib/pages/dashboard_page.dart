import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../notifications/supabase_notif.dart';

class DashboardPage extends StatefulWidget {
  final String deviceId;
  final Map<String, dynamic> sensorData;
  final String userId;

  const DashboardPage({
    super.key,
    required this.deviceId,
    required this.sensorData,
    required this.userId,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double sliderValue = 0.5;
  bool isAuto = true; // Will be overridden by RTDB listener
  String? actionMessage;

  DatabaseReference? commandRef;
  DatabaseReference? sensorDataRef;

  StreamSubscription<DatabaseEvent>? sensorListener;
  StreamSubscription<DatabaseEvent>? autoModeListener;
  StreamSubscription<DatabaseEvent>? positionListener;

  bool isOnline = true;
  DateTime? lastUpdateTime;
  Timer? offlineTimer;
  static const int offlineThresholdSec = 30;

  String deviceName = "Device";

  @override
  void initState() {
    super.initState();

    _loadDeviceName();
    _loadSupabaseOnlineStatus();

    final safeDeviceId = widget.deviceId.replaceAll(":", "_");

    commandRef =
        FirebaseDatabase.instance.ref("devices/$safeDeviceId/commands");
    sensorDataRef =
        FirebaseDatabase.instance.ref("devices/$safeDeviceId/sensorData");

    // 🔥 Listen to sensor updates (for online/offline detection)
    sensorListener = sensorDataRef!.onValue.listen((event) {
      if (event.snapshot.value == null) return;

      setState(() {
        final wasOffline = !isOnline;
        lastUpdateTime = DateTime.now();
        isOnline = true;

        if (wasOffline) {
          sendSupabaseNotif(
            "Device Online",
            "SmartPayan device is back online.",
            "online",
            safeDeviceId,
          );
        }
      });
    });

    // 🔥 LISTEN FOR autoMode CHANGES (UI always matches RTDB)
    autoModeListener =
        commandRef!.child("autoMode").onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is bool) {
        setState(() {
          isAuto = value;
          if (isAuto) {
            actionMessage = null; // when switching back to auto
          }
        });
      }
    });

    // 🔥 LISTEN FOR clotheslinePosition CHANGES IN MANUAL MODE
    positionListener =
        commandRef!.child("clotheslinePosition").onValue.listen((event) {
      final value = event.snapshot.value;

      if (value is double && !isAuto) {
        setState(() {
          sliderValue = value;
        });
      }
    });

    // offline detection
    offlineTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkOffline());
  }

  @override
  void dispose() {
    sensorListener?.cancel();
    autoModeListener?.cancel();
    positionListener?.cancel();
    offlineTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceName() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.userId)
          .collection("deviceInfo")
          .doc(widget.deviceId)
          .get();

      if (snap.exists) {
        setState(() {
          deviceName = snap.data()?["name"] ?? "Device";
        });
      }
    } catch (e) {
      print("Error loading device name: $e");
    }
  }

  Future<void> _loadSupabaseOnlineStatus() async {
    try {
      final response = await Supabase.instance.client
          .from('devices')
          .select('is_online, last_seen')
          .eq('device_id', widget.deviceId)
          .single();

      final online = response['is_online'] == true;

      setState(() {
        isOnline = online;
        lastUpdateTime = online
            ? DateTime.now()
            : (response['last_seen'] != null
                ? DateTime.parse(response['last_seen'])
                : null);
      });
    } catch (e) {
      print("Supabase status error: $e");
    }
  }

  void _checkOffline() {
    if (lastUpdateTime == null) return;

    final diff = DateTime.now().difference(lastUpdateTime!);
    if (diff.inSeconds > offlineThresholdSec && isOnline) {
      sendSupabaseNotif(
        "Device Offline",
        "SmartPayan device has stopped sending sensor data.",
        "offline",
        widget.deviceId.replaceAll(':', '_'),
      );
      setState(() => isOnline = false);
    }
  }

  void sendCommand(String key, dynamic value) {
    commandRef?.update({key: value});
  }

  double _sliderFromState(String? state) {
    if (state == "extended") return 1.0;
    if (state == "retracted") return 0.0;
    return 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.sensorData;

    final light = (data['lightLevel'] as num?)?.toInt() ?? 600;
    final rain = data['rain'] == true;
    final humidity = (data['humidity'] as num?)?.toInt() ?? 70;
    final temperature = (data['temperature'] as num?)?.toDouble() ?? 25.0;
    final currentState = data['state'] as String?;

    if (isAuto) {
      sliderValue = _sliderFromState(currentState);
      actionMessage = null;
    }

    if (currentState ==
        (sliderValue == 1 ? "extended" : "retracted")) {
      actionMessage = null;
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // TITLE + ONLINE DOT
            Row(
              children: [
                Text(
                  deviceName,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.greenAccent : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),

            if (!isOnline)
              const Text(
                "Device Offline — Showing cached data",
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),

            const SizedBox(height: 20),

            // WEATHER + AUTO/MANUAL SWITCH
            _glassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _statusTile(
                    icon: Icons.cloud,
                    label: "Rain",
                    value: rain ? "Detected" : "None",
                    color: rain ? Colors.red : Colors.greenAccent,
                  ),

                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.settings,
                            color: Colors.white, size: 32),
                        onPressed: () {
                          final newMode = !isAuto;
                          sendCommand("autoMode", newMode);
                          setState(() => isAuto = newMode);
                        },
                      ),
                      Text(
                        isAuto ? "Auto Mode" : "Manual Mode",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      )
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 18),

            // SENSOR STATS
            _glassCard(
              child: Column(
                children: [
                  _sensorTile(
                      icon: Icons.wb_sunny,
                      label: "Light Level",
                      value: "$light lx"),
                  _divider(),
                  _sensorTile(
                      icon: Icons.water_drop,
                      label: "Humidity",
                      value: "$humidity%"),
                  _divider(),
                  _sensorTile(
                      icon: Icons.thermostat,
                      label: "Temperature",
                      value: "${temperature.toStringAsFixed(1)}°C"),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // CLOTHESLINE CONTROL BLOCK
            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // HEADER ROW
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Clothesline Position",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 16)),
                      InkWell(
                        onTap: () {
                          final newMode = !isAuto;
                          sendCommand("autoMode", newMode);
                          setState(() => isAuto = newMode);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isAuto ? "Auto" : "Manual",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    ],
                  ),

                  // SLIDER
                  Slider(
                    value: sliderValue,
                    divisions: 1,
                    min: 0,
                    max: 1,
                    activeColor:
                        isAuto ? Colors.grey : Colors.greenAccent,
                    onChanged: isAuto
                        ? null
                        : (value) {
                            final newValue = value.roundToDouble();
                            setState(() {
                              sliderValue = newValue;
                              actionMessage = newValue == 1.0
                                  ? "Clothesline extending..."
                                  : "Clothesline retracting...";
                            });
                            sendCommand("clotheslinePosition", newValue);
                          },
                  ),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Retracted",
                          style: TextStyle(color: Colors.white70)),
                      Text("Extended",
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),

                  // ACTION MESSAGE
                  if (actionMessage != null)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          actionMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: child,
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _sensorTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 30),
        const SizedBox(width: 14),
        Text(label,
            style:
                const TextStyle(fontSize: 16, color: Colors.white70)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _divider() =>
      Divider(color: Colors.white.withOpacity(0.3));
}
