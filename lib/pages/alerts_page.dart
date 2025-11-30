import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../backgrounds/background_engine.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<Map<String, dynamic>> alerts = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAlerts();
    setupRealtimeSubscription();
  }

  // Fetch latest notifications from Supabase
  Future<void> fetchAlerts() async {
    final supabase = Supabase.instance.client;

    try {
      final response = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        alerts = List<Map<String, dynamic>>.from(response);
        isLoading = false;
      });
    } catch (e) {
      print("Fetch alerts error: $e");
      setState(() => isLoading = false);
    }
  }

  // Realtime subscription for instant updates
  void setupRealtimeSubscription() {
  final supabase = Supabase.instance.client;

  supabase.channel('public:notifications')
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        final newRow = payload.newRecord;
        if (newRow != null) {
          setState(() {
            alerts.insert(0, newRow); // prepend newest alert
          });
        }
      },
    )
    .subscribe();
}


  @override
  Widget build(BuildContext context) {
    final mode = BackgroundProvider.of(context).mode;

    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: RefreshIndicator(
              onRefresh: fetchAlerts,
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: alerts.length,
                      itemBuilder: (context, i) {
                        final alert = alerts[i];

                        // Parse timestamp
                        final createdAt = DateTime.tryParse(alert['created_at'] ?? "") ??
                            DateTime.now();
                        final timeString =
                            "${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}";

                        return _alertCard(
                          mode: mode,
                          msg: alert['message'] ?? 'No message',
                          time: timeString,
                        );
                      },
                    ),
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
          const Icon(Icons.notifications, color: Colors.white, size: 28),
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
