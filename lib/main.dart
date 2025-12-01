import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Background engine & notifications
import 'backgrounds/background_engine.dart';
import 'notifications/notifications.dart';

// Pages
import 'pages/dashboard_page.dart';
import 'pages/alerts_page.dart';
import 'pages/settings_page.dart';
import 'pages/init_page.dart';
import 'pages/login_page.dart';
import 'pages/create_account.dart';
import 'pages/setup_device.dart';

// -----------------------------------------------------------
// LOCAL NOTIFICATION PLUGIN
// -----------------------------------------------------------

final FlutterLocalNotificationsPlugin localNotif =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel mainChannel = AndroidNotificationChannel(
  'default_channel',
  'SmartPayan Alerts',
  description: 'Notifications for device events',
  importance: Importance.high,
);

// REQUIRED FOR ANDROID BACKGROUND HANDLING
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;

  final notifTitle = data['title'] ?? "SmartPayan Alert";
  final notifBody = data['body'] ?? "";

  localNotif.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,   // UNIQUE ID
    notifTitle,
    notifBody,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'default_channel',
        'SmartPayan Alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

// -----------------------------------------------------------
// MAIN INIT
// -----------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Init Supabase
  await Supabase.initialize(
    url: 'https://dbwhtzoahlzgpiuhqvlv.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRid2h0em9haGx6Z3BpdWhxdmx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0NzM5ODYsImV4cCI6MjA4MDA0OTk4Nn0.Ny81j8nYmPteq6apMqIsJAHaNT2erIkXPNBDe7UCvP8',
  );

  // Notification permission
  await FirebaseMessaging.instance.requestPermission();

  // Local Notification Initialization
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );

  await localNotif.initialize(initSettings);

  // Create notification channel
  final androidPlugin =
      localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(mainChannel);

  // Background handler register
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

// -----------------------------------------------------------
// MAIN APP WIDGET
// -----------------------------------------------------------

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/init',
      routes: {
        '/init': (context) => InitializationPage(),
        '/login': (context) => LoginPage(),
        '/create-account': (context) => CreateAccountPage(),
        '/setup-device': (context) {
          final userDocId =
              ModalRoute.of(context)!.settings.arguments as String;
          return SetupDevicePage(userDocId: userDocId);
        }
      },
    );
  }
}

// -----------------------------------------------------------
// HOME SCREEN
// -----------------------------------------------------------

class HomeScreen extends StatefulWidget {
  final String userDocId;
  final String deviceId;

  const HomeScreen({
    super.key,
    required this.userDocId,
    required this.deviceId,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  Map<String, dynamic> sensorData = {
    'lightLevel': 600,
    'rain': false,
    'humidity': 70,
    'temperature': 25.0,
  };

  bool isOnline = false;
  DatabaseReference? ref;

  @override
  void initState() {
    super.initState();

    final safeId = widget.deviceId.replaceAll(':', '_');

    // RTDB listener
    ref = FirebaseDatabase.instance.ref("devices/$safeId/sensorData");

    ref!.onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.value == null) {
        setState(() => isOnline = false);
        return;
      }

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      setState(() {
        sensorData = data;
        isOnline = true;
      });
    });

    // Register this device's FCM token
    registerDeviceToken(safeId);

    // FOREGROUND PUSH NOTIFICATIONS
    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;

      final notifTitle = data['title'] ?? "SmartPayan Alert";
      final notifBody = data['body'] ?? "";

      localNotif.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000, // UNIQUE ID
        notifTitle,
        notifBody,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_channel',
            'SmartPayan Alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  // -----------------------------------------------------------
  // TOKEN REGISTRATION (corrected)
  // -----------------------------------------------------------

  Future<void> registerDeviceToken(String safeDeviceId) async {
    final fcm = FirebaseMessaging.instance;

    // 1 — Get token
    final token = await fcm.getToken();
    if (token == null) return;

    print("FCM Token Now: $token");

    // 2 — Clear previous tokens for this device
    await Supabase.instance.client
        .from('device_tokens')
        .delete()
        .eq('device_id', safeDeviceId);

    // 3 — Insert new fresh token
    await Supabase.instance.client.from("device_tokens").insert({
      "device_id": safeDeviceId,
      "fcm_token": token,
      "updated_at": DateTime.now().toIso8601String(),
    });

    // 4 — Listen for token refresh
    fcm.onTokenRefresh.listen((newToken) async {
      // Wipe old tokens again
      await Supabase.instance.client
          .from('device_tokens')
          .delete()
          .eq('device_id', safeDeviceId);

      // Insert new
      await Supabase.instance.client.from("device_tokens").insert({
        "device_id": safeDeviceId,
        "fcm_token": newToken,
        "updated_at": DateTime.now().toIso8601String(),
      });
    });
  }

  @override
  void dispose() {
    ref?.onValue.drain();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(
        deviceId: widget.deviceId,
        sensorData: sensorData,
      ),
      const AlertsPage(),
      SettingsPage(deviceId: widget.deviceId, userDocId: widget.userDocId),
    ];

    return BackgroundEngine(
      light: (sensorData['lightLevel'] as num?)?.toInt() ?? 600,
      rain: sensorData['rain'] == true,
      humidity: (sensorData['humidity'] as num?)?.toInt() ?? 70,
      sensorsOnline: isOnline,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("SmartPayan"),
          backgroundColor: Colors.blueGrey.withOpacity(0.3),
        ),
        body: pages[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.blueGrey.withOpacity(0.2),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.dashboard), label: "Dashboard"),
            BottomNavigationBarItem(
                icon: Icon(Icons.notifications), label: "Alerts"),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings), label: "Settings"),
          ],
        ),
      ),
    );
  }
}
