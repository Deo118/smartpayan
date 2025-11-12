import 'dart:math';
import 'package:flutter/material.dart';

enum BackgroundMode {
  day,
  night,
  rainy,
  cloudy,
  sunrise,
}

class BackgroundProvider extends InheritedWidget{
  final BackgroundMode mode;

  const BackgroundProvider({
    super.key,
    required this.mode,
    required super.child,
  });

  static BackgroundProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BackgroundProvider>()!;
  }

  @override
  bool updateShouldNotify(covariant BackgroundProvider oldWidget) {
    return oldWidget.mode !=mode;
  }
}


class BackgroundEngine extends StatelessWidget {
  final int light;        
  final bool rain;        
  final int humidity;     
  final bool sensorsOnline;
  final Widget? child;

  const BackgroundEngine({
    super.key,
    required this.light,
    required this.rain,
    required this.humidity,
    this.sensorsOnline = true,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final String image = _selectBackground();

    BackgroundMode currentMode;

    if (!sensorsOnline){
      final hour = DateTime.now().hour;
      if (hour < 6){
        currentMode = BackgroundMode.night;
      } else if (hour < 8){
        currentMode = BackgroundMode.sunrise;
      } else if (hour < 18){
        currentMode = BackgroundMode.day;
      } else {
        currentMode = BackgroundMode.night;
      }
    } else if (rain){
      currentMode = light < 200 ? BackgroundMode.night : BackgroundMode.rainy;
    } else if (light < 200) {
      currentMode = BackgroundMode.night;
    } else if (light < 500){
      currentMode = BackgroundMode.sunrise;
    } else if (humidity > 70){
      currentMode = BackgroundMode.cloudy;
    } else {
      currentMode = BackgroundMode.day;
    }

    return BackgroundProvider(
      mode: currentMode,  
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/$image",
              fit: BoxFit.cover,
            ),
          ),
      
        // Rain particles
        if (rain) const Positioned.fill(child: _RainParticles()),

        // Stars 
        if (!rain && light < 200)
          const Positioned.fill(child: _StarParticles()),

        // Foreground child
        if (child != null) child!,
        ],
      ),
    );
  }

  String _selectBackground() {
    // Fallback when ESP32 data unavailable
    if (!sensorsOnline) {
      final hour = DateTime.now().hour;
      if (hour < 6) return "1.png";
      if (hour < 8) return "3.png";
      if (hour < 18) return "4.png";
      return "1.png";
    }

    if (rain) {
      return light < 200
          ? "1.png"    // Rain + night
          : "2.png"; // Rain + day
    }

    // Night
    if (light < 200) return "1.png";

    // Dawn/Dusk
    if (light < 500) return "3.png";

    // Humid/Misty
    if (humidity > 70) return "5.png";

    // Bright day
    return "4.png";
  }
}

//Stars
class _StarParticles extends StatefulWidget {
  const _StarParticles();

  @override
  State<_StarParticles> createState() => _StarParticlesState();
}


class _StarParticlesState extends State<_StarParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Offset> stars = [];
  List<double> brightness = [];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    final random = Random();
    for (int i = 0; i < 60; i++) {
      stars.add(Offset(random.nextDouble(), random.nextDouble()));
      brightness.add(random.nextDouble());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return SizedBox.expand(
          child: CustomPaint(
            painter: _StarPainter(stars, brightness, _controller.value),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

//stars
class _StarPainter extends CustomPainter {
  final List<Offset> stars;
  final List<double> brightness;
  final double flicker;

  _StarPainter(this.stars, this.brightness, this.flicker);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (int i = 0; i < stars.length; i++) {
      double opacity = ((brightness[i] + flicker) % 1.0).clamp(0.0, 1.0);

      paint.color = Color.fromRGBO(255, 255, 255, opacity);

      Offset pos = Offset(
        stars[i].dx * size.width,
        stars[i].dy * size.height,
      );

      canvas.drawCircle(pos, 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}

//rain
class _RainParticles extends StatefulWidget {
  const _RainParticles();

  @override
  State<_RainParticles> createState() => _RainParticlesState();
}

//Rain Particles
class _RainParticlesState extends State<_RainParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Offset> drops = [];
  final random = Random();

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    // 60 rain drops
    for (int i = 0; i < 60; i++) {
      drops.add(Offset(random.nextDouble(), random.nextDouble()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return SizedBox.expand(
          child: CustomPaint(
            painter: _RainPainter(drops, _controller.value),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _RainPainter extends CustomPainter {
  final List<Offset> drops;
  final double animation;

  _RainPainter(this.drops, this.animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.4)
      ..strokeWidth = 1.4;

    for (var drop in drops) {
      double dx = drop.dx * size.width;
      double dy =
          (drop.dy * size.height + animation * size.height) % size.height;

      canvas.drawLine(
        Offset(dx, dy),
        Offset(dx, dy + 8),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_) => true;
}
