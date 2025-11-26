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

  DatabaseReference? commandRef;

  @override
  void initState() {
    super.initState();
    commandRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/commands');
  }

  void sendCommand(String key, dynamic value) {
    commandRef?.update({key: value});
  }

  @override
  Widget build(BuildContext context) {
    final mode = BackgroundProvider.of(context).mode;

    // Use sensor data from props (passed from HomeScreen)
    int light = widget.sensorData['lightLevel'] ?? 600;
    bool rain = widget.sensorData['rain'] ?? false;
    int humidity = widget.sensorData['humidity'] ?? 70;
    double temperature = widget.sensorData['temperature'] ?? 25.0;
    bool isOnline = widget.isOnline;

    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PAGE TITLE
                  Text(
                    "Dashboard",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: (mode == BackgroundMode.night || mode == BackgroundMode.rainy)
                          ? Colors.white
                          : Colors.white,
                      shadows: [
                        Shadow(
                          blurRadius: 6,
                          color: Colors.black.withOpacity(0.6),
                        )
                      ],
                    ),
                  ),

                  // Online status
                  if (!isOnline)
                    const Text("Device Offline - Showing cached data", style: TextStyle(color: Colors.red)),

                  const SizedBox(height: 20),

                  // STATUS CARD
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

                        // Auto/Manual mode next to rain status
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.settings, 
                                color: Colors.white,
                                size: 32,
                              ),
                              onPressed: () {
                                setState(() {
                                  isAuto = !isAuto;
                                });
                                sendCommand('autoMode', isAuto);  // Send to RTDB
                              },
                            ),
                            Text(
                              isAuto ? "Auto Mode" : "Manual Mode",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // SENSOR CARDS
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

                  // CONTROL SLIDER
                  _glassCard(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Clothesline Position",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                            // Toggle Auto/Manual button
                            InkWell(
                              onTap: () {
                                setState(() {
                                  isAuto = !isAuto;
                                });
                                sendCommand('autoMode', isAuto);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Text(
                                  isAuto ? "Auto" : "Manual",
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: sliderValue,
                          onChanged: (val) {
                            setState(() {
                              sliderValue = val;
                            });
                            sendCommand('clotheslinePosition', val);  // Send to RTDB
                          },
                          min: 0,
                          max: 1,
                          divisions: 2,
                          activeColor: Colors.greenAccent,
                          inactiveColor: Colors.white30,
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text("Retracted", style: TextStyle(color: Colors.white70)),
                            Text("Extended", style: TextStyle(color: Colors.white70)),
                          ],
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
        Text(label,
            style: TextStyle(color: Colors.white70, fontSize: 14)),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.4))
            ],
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
        Text(
          label,
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
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

  Widget _divider() => Divider(color: Colors.white.withOpacity(0.3));
}