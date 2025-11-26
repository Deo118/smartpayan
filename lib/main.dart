import 'package:flutter/material.dart';
import 'package:smartpayan/backgrounds/background_engine.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';  // Added for RTDB listener in HomeScreen

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
          final userDocId = ModalRoute.of(context)!.settings.arguments as String;
          return SetupDevicePage(userDocId: userDocId);
        }
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String userDocId;
  final String deviceId;

  const HomeScreen({super.key, required this.userDocId, required this.deviceId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Lifted sensor data from DashboardPage 
  Map<String, dynamic> sensorData = {
    'lightLevel': 600,
    'rain': false,
    'humidity': 70,
    'temperature': 25.0,
  };
  bool isOnline = false;
  DatabaseReference? sensorRef;

  @override
  void initState() {
    super.initState();
    // RTDB listener 
    sensorRef = FirebaseDatabase.instance.ref('devices/${widget.deviceId}/sensorData');
    sensorRef!.onValue.listen((event) {
      if (event.snapshot.value != null) {
        setState(() {
          sensorData = Map<String, dynamic>.from(event.snapshot.value as Map);
          isOnline = true;
        });
      } else {
        setState(() => isOnline = false);
      }
    });
  }

  @override
  void dispose() {
    sensorRef?.onValue.drain();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Extract values for props (to pass to BackgroundEngine and DashboardPage)
    int light = sensorData['lightLevel'] ?? 600;
    bool rain = sensorData['rain'] ?? false;
    int humidity = sensorData['humidity'] ?? 70;

    final List<Widget> _pages = [
      DashboardPage(
        deviceId: widget.deviceId,
        sensorData: sensorData,  // Pass sensor data as props
        isOnline: isOnline,
      ),
      AlertsPage(),
      SettingsPage(deviceId: widget.deviceId, userDocId: widget.userDocId),
    ];

    return BackgroundEngine(
      light: light,  // Pass dynamic sensor values for real-time background updates
      rain: rain,
      humidity: humidity,
      sensorsOnline: isOnline,
      child: Builder(
        builder: (context) {
          final mode = BackgroundProvider.of(context).mode;

          Color appBarColor;
          Color navBarColor;

          switch (mode) {
            case BackgroundMode.night:
              appBarColor = Colors.blueGrey.withOpacity(0.4);
              navBarColor = Colors.black.withOpacity(0.3);
              break;
            case BackgroundMode.rainy:
              appBarColor = Colors.blueGrey.withOpacity(0.4);
              navBarColor = Colors.blueGrey.withOpacity(0.3);
              break;
            case BackgroundMode.sunrise:
              appBarColor = Colors.blueGrey.withOpacity(0.35);
              navBarColor = Colors.white.withOpacity(0.3);
              break;
            case BackgroundMode.day:
              appBarColor = Colors.white.withOpacity(0.15);
              navBarColor = Colors.white.withOpacity(0.12);
              break;
            case BackgroundMode.cloudy:
              appBarColor = Colors.grey.withOpacity(0.3);
              navBarColor = Colors.grey.withOpacity(0.25);
              break;
          }

          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text("SmartPayan", 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
              backgroundColor: appBarColor,
              elevation: 0,
            ),
            body: _pages[_selectedIndex],
            bottomNavigationBar: BottomNavigationBar(
              backgroundColor: navBarColor,
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.white70,
              currentIndex: _selectedIndex,
              onTap: _onItemTapped,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: "Dashboard",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.notifications),
                  label: "Alerts",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: "Settings",
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}