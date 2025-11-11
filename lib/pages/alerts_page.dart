import 'package:flutter/material.dart';
import '../backgrounds/background_engine.dart';

class AlertsPage extends StatelessWidget {
  final List<Map<String, String>> alerts = [
    {"time": "10:42 AM", "msg": "Rain detected — retracting clothesline"},
    {"time": "9:18 AM", "msg": "Humidity high (87%)"},
    {"time": "8:05 AM", "msg": "Sunrise detected — switching to day mode"},
  ];

  @override
  Widget build(BuildContext context) {
    // Access the universal background mode
    final mode = BackgroundProvider.of(context).mode;

    return Stack(
      children: [
        // Background already handled by BackgroundEngine in main.dart

        // Foreground UI
        Positioned.fill(
          child: SafeArea(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              itemBuilder: (context, i) {
                return _alertCard(
                  mode: mode,
                  msg: alerts[i]["msg"]!,
                  time: alerts[i]["time"]!,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _alertCard({
    required BackgroundMode mode,
    required String msg,
    required String time,
  }) {
    // Adjust card color based on mode
    Color cardColor;
    switch (mode) {
      case BackgroundMode.night:
        cardColor = Colors.white.withOpacity(0.15);
        break;
      case BackgroundMode.rainy:
        cardColor = Colors.white.withOpacity(0.12);
        break;
      default:
        cardColor = Colors.white.withOpacity(0.18);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Text(
            time,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
