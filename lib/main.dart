import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'backgrounds/background_engine.dart';

// Pages
import 'pages/dashboard_page.dart';
import 'pages/alerts_page.dart';
import 'pages/settings_page.dart';
import 'pages/init_page.dart';
import 'pages/login_page.dart';
import 'pages/create_account.dart';
import 'pages/setup_device.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  print("Firebase initialized");
  runApp(const MyApp());
}

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

class HomeScreen extends StatefulWidget {
  final String userDocId;
  final String deviceId; // already sanitized

  const HomeScreen(
      {super.key, required this.userDocId, required this.deviceId});

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
    ref = FirebaseDatabase.instance.ref("devices/$safeId/sensorData");

    ref!.onValue.listen((event) {
      try {
        final snap = event.snapshot;
        if (snap.value == null) {
          if (mounted) setState(() => isOnline = false);
          return;
        }

        final data = Map<String, dynamic>.from(snap.value as Map);

        if (mounted) {
          setState(() {
            sensorData = data;
            isOnline = true;
          });
        }
      } catch (e) {
        debugPrint("RTDB listener error: $e");
      }
    });
  }

  @override
  void dispose() {
    ref?.onValue.drain();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int light = (sensorData['lightLevel'] as num?)?.toInt() ?? 600;
    bool rain = sensorData['rain'] == true;
    int humidity = (sensorData['humidity'] as num?)?.toInt() ?? 70;

    final pages = [
      DashboardPage(
        deviceId: widget.deviceId,
        sensorData: sensorData,
        isOnline: isOnline,
      ),
      AlertsPage(),
      SettingsPage(
        deviceId: widget.deviceId,
        userDocId: widget.userDocId,
      ),
    ];

    return BackgroundEngine(
      light: light,
      rain: rain,
      humidity: humidity,
      sensorsOnline: isOnline,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("SmartPayan", style: TextStyle(color: Colors.white,)),
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
