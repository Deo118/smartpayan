import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  late RealtimeChannel notifChannel;
  final Set<dynamic> _deletingIds = {};

  bool dontAskAgainDelete = false;

  @override
  void initState() {
    super.initState();
    loadDeletePreference();
    fetchAlerts();
    setupRealtimeSubscription();
  }

  Future<void> loadDeletePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      dontAskAgainDelete = prefs.getBool("dontAskAgainDelete") ?? false;
    });
  }

  Future<void> saveDeletePreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("dontAskAgainDelete", value);
    setState(() {
      dontAskAgainDelete = value;
    });
  }

  Future<void> fetchAlerts() async {
    final supabase = Supabase.instance.client;

    try {
      final result = await supabase
          .from('notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      if (mounted) {
        setState(() {
          alerts = List<Map<String, dynamic>>.from(result);
          isLoading = false;
        });
      }
    } catch (e) {
      print("Fetch error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  void setupRealtimeSubscription() {
    final supabase = Supabase.instance.client;

    notifChannel = supabase
        .channel('public:notifications')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      callback: (payload) {
        final newRow = payload.newRecord;
        if (newRow != null && mounted) {
          setState(() => alerts.insert(0, newRow));
        }
      },
    )
        .subscribe();
  }

  Future<void> deleteOne(dynamic id, int index) async {
    if (id == null) return;
    if (_deletingIds.contains(id)) return;

    final supabase = Supabase.instance.client;

    bool allowDelete = dontAskAgainDelete;

    if (!dontAskAgainDelete) {
      bool tempDontAskAgain = false;

      allowDelete = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text("Delete alert?"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("This action cannot be undone."),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: tempDontAskAgain,
                      onChanged: (v) {
                        setStateDialog(() => tempDontAskAgain = v ?? false);
                      },
                      title: const Text("Do not ask again"),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text("Delete", style: TextStyle(color: Colors.red)),
                  ),
                ],
              );
            },
          );
        },
      ) ??
          false;

      if (allowDelete && tempDontAskAgain) saveDeletePreference(true);
    }

    if (!allowDelete) return;

    final removedAlert = alerts[index];

    setState(() {
      _deletingIds.add(id);
      alerts.removeAt(index);
    });

    try {
      await supabase.from("notifications").delete().eq("id", id);
    } catch (e) {
      if (mounted) {
        setState(() {
          alerts.insert(index.clamp(0, alerts.length), removedAlert);
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete alert: $e")),
      );
    }

    if (mounted) {
      setState(() => _deletingIds.remove(id));
    }
  }

  Future<void> deleteAllAlerts() async {
    final supabase = Supabase.instance.client;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete all alerts?"),
        content: const Text("This action will permanently clear all alerts."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ??
        false;

    if (!confirm) return;

    final previous = List<Map<String, dynamic>>.from(alerts);
    setState(() => alerts.clear());

    try {
      await supabase
          .from("notifications")
          .delete()
          .neq("id", "00000000-0000-0000-0000-000000000000");
    } catch (e) {
      setState(() => alerts = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to delete all: $e")),
      );
    }
  }

  // ✅ FIXED FORMATTER — ALWAYS CORRECT PH TIME (UTC+8)
  String formatLocalTime(String timestamp) {
    try {
      final dtUtc = DateTime.parse(timestamp).toUtc();
      final phTime = dtUtc.add(const Duration(hours: 8));

      final hour = phTime.hour > 12
          ? phTime.hour - 12
          : phTime.hour == 0
          ? 12
          : phTime.hour;

      final minute = phTime.minute.toString().padLeft(2, '0');
      final ampm = phTime.hour >= 12 ? "PM" : "AM";

      return "$hour:$minute $ampm";
    } catch (_) {
      return "--:--";
    }
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(notifChannel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = BackgroundProvider.of(context).mode;

    return Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: fetchAlerts,
                    child: isLoading
                        ? const Center(
                        child: CircularProgressIndicator(color: Colors.white))
                        : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: alerts.length,
                      itemBuilder: (context, index) {
                        final alert = alerts[index];
                        final time = formatLocalTime(alert['created_at'] ?? "");

                        return Dismissible(
                          key: Key(alert['id'].toString()),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => deleteOne(alert['id'], index),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: _alertCard(
                            mode: mode,
                            msg: alert['message'],
                            time: time,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Alerts",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: deleteAllAlerts,
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 30),
            tooltip: "Delete all alerts",
          ),
        ],
      ),
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
