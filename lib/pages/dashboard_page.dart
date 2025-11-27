import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../backgrounds/background_engine.dart';

class DashboardPage extends StatefulWidget {
  final String deviceId;
  final Map<String, dynamic> sensorData;
  final bool isOnline;

  const DashboardPage({
    super.key,
    required this.deviceId,
    required this.sensorData,
    required this.isOnline,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  double sliderValue = 0.5;
  bool isAuto = true;
  String? actionMessage; 
  DatabaseReference? commandRef;

  @override
  void initState() {
    super.initState();
    commandRef = FirebaseDatabase.instance.ref(
      'devices/${widget.deviceId}/commands',
    );
  }

  void sendCommand(String key, dynamic value) {
    commandRef?.update({key: value});
  }

  // Helper to get slider value from RTDB state
  double _getSliderFromState(String? state) {
    if (state == "extended") return 1.0;
    if (state == "retracted") return 0.0;
    return 0.5; // Default (though now unused)
  }

  @override
  Widget build(BuildContext context) {
    final mode = BackgroundProvider.of(context).mode;

    final data = widget.sensorData;

    int light = (data['lightLevel'] as num?)?.toInt() ?? 600;
    bool rain = data['rain'] == true;
    int humidity = (data['humidity'] as num?)?.toInt() ?? 70;
    double temperature = (data['temperature'] as num?)?.toDouble() ?? 25.0;
    bool online = widget.isOnline;
    String? clotheslineState = data['state'] as String?;

    // Update slider based on mode
    if (isAuto) {
      sliderValue = _getSliderFromState(clotheslineState); // Follow RTDB in auto mode
      actionMessage = null; // Clear message in auto mode
    } else {
      // In manual mode, slider value is user-controlled
    }

    // Clear message if RTDB state matches slider value
    if (clotheslineState == (sliderValue == 1.0 ? "extended" : "retracted")) {
      actionMessage = null;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Dashboard",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black.withOpacity(0.6),
                        )
                      ],
                    ),
                  ),

                  if (!online)
                    const Text(
                      "Device Offline - Showing cached data",
                      style: TextStyle(color: Colors.red),
                    ),

                  const SizedBox(height: 20),

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
                                setState(() => isAuto = !isAuto);
                                sendCommand('autoMode', isAuto);
                              },
                            ),
                            Text(
                              isAuto ? "Auto Mode" : "Manual Mode",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  _glassCard(
                    child: Column(
                      children: [
                        _sensorTile(
                          icon: Icons.wb_sunny,
                          label: "Light Level",
                          value: "$light lx",
                        ),
                        _divider(),
                        _sensorTile(
                          icon: Icons.water_drop,
                          label: "Humidity",
                          value: "$humidity%",
                        ),
                        _divider(),
                        _sensorTile(
                          icon: Icons.thermostat,
                          label: "Temperature",
                          value: "${temperature.toStringAsFixed(1)}°C",
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  _glassCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Clothesline Position",
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() => isAuto = !isAuto);
                                sendCommand('autoMode', isAuto);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.white30),
                                ),
                                child: Text(
                                  isAuto ? "Auto" : "Manual",
                                  style:
                                      const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: sliderValue,
                          onChanged: isAuto
                              ? null // Disabled in auto mode
                              : (v) {
                                  double newValue = v.roundToDouble();
                                  setState(() {
                                    sliderValue = newValue;
                                    actionMessage = newValue == 1.0
                                        ? "Clothesline extending..."
                                        : "Clothesline retracting...";
                                  });
                                  sendCommand('clotheslinePosition', newValue);
                                  // Debug: Print to console to verify
                                  print("Slider changed to $newValue, message: $actionMessage");
                                },
                          min: 0,
                          max: 1,
                          divisions: 1, // Always 1: Only 0 and 1 allowed
                          activeColor: isAuto ? Colors.grey : Colors.greenAccent, // Gray in auto
                          inactiveColor: Colors.white30,
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
                        if (actionMessage != null) // Show message if present
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              actionMessage!,
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ],
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
          )
        ],
      ),
      child: child,
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    Color color = Colors.white,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        )
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
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.white70)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        )
      ],
    );
  }

  Widget _divider() =>
      Divider(color: Colors.white.withOpacity(0.3));
}