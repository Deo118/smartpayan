import 'package:flutter/material.dart';
import 'package:smartpayan/backgrounds/background_engine.dart';
import 'pages/dashboard_page.dart';
import 'pages/alerts_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    //temp sensor values
    int light = 100; //0 to 1k
    bool rain = false;
    int humidity = 30;
    double temperature = 8;

    final List<Widget> _pages = [
      DashboardPage(
        light: light,
        rain: rain,
        humidity: humidity,
        temperature: temperature,
      ),
      AlertsPage(),
      SettingsPage(),
    ];

    return BackgroundEngine(
      light: light,
      rain: rain,
      humidity: humidity,
      sensorsOnline: true,
      // Wrap entire Scaffold in Builder to get currentMode from BackgroundProvider
      child: Builder(
        builder: (context) {
          final mode = BackgroundProvider.of(context).mode;

          // Dynamic AppBar & BottomNavigationBar colors
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
            // Make scaffold background transparent so background image is visible
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: const Text("SmartPayan"),
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
