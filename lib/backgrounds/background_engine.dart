import 'dart:math';
import 'package:flutter/material.dart';

enum BackgroundMode {
  day,
  night,
  rainy,
  cloudy,
  sunrise,
}

class BackgroundProvider extends InheritedWidget {
  final BackgroundMode mode;

  const BackgroundProvider({
    super.key,
    required this.mode,
    required super.child,
  });

  static BackgroundProvider? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BackgroundProvider>();
  }

  static BackgroundProvider of(BuildContext context) {
    final provider = maybeOf(context);
    return provider ??
        BackgroundProvider(
          mode: BackgroundMode.day,
          child: const SizedBox(),
        );
  }

  @override
  bool updateShouldNotify(covariant BackgroundProvider oldWidget) {
    return oldWidget.mode != mode;
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

    BackgroundMode mode;

    if (!sensorsOnline) {
      final hour = DateTime.now().hour;
      if (hour < 6) mode = BackgroundMode.night;
      else if (hour < 8) mode = BackgroundMode.sunrise;
      else if (hour < 18) mode = BackgroundMode.day;
      else mode = BackgroundMode.night;
    } else if (rain) {
      mode = light < 200 ? BackgroundMode.night : BackgroundMode.rainy;
    } else if (light < 200) {
      mode = BackgroundMode.night;
    } else if (light < 500) {
      mode = BackgroundMode.sunrise;
    } else if (humidity > 70) {
      mode = BackgroundMode.cloudy;
    } else {
      mode = BackgroundMode.day;
    }

    return BackgroundProvider(
      mode: mode,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/$image",
              fit: BoxFit.cover,
            ),
          ),

          if (rain) const Positioned.fill(child: _RainParticles()),
          if (!rain && light < 200) const Positioned.fill(child: _StarParticles()),

          if (child != null) child!,
        ],
      ),
    );
  }

  String _selectBackground() {
    if (!sensorsOnline) {
      final hour = DateTime.now().hour;
      if (hour < 6) return "night.png";
      if (hour < 8) return "sunrise.png";
      if (hour < 18) return "day.png";
      return "night.png";
    }

    if (rain) {
      return light < 200 ? "night.png" : "rainyday.png";
    }

    if (light < 200) return "night.png";
    if (light < 500) return "sunrise.png";
    if (humidity > 70) return "cloudy.png";

    return "day.png";
  }
}

class _StarParticles extends StatefulWidget {
  const _StarParticles();

  @override
  State<_StarParticles> createState() => _StarParticlesState();
}

class _StarParticlesState extends State<_StarParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Offset> stars = [];
  final List<double> brightness = [];

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    final random = Random();
    for (int i = 0; i < 30; i++) {
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
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _StarPainter(stars, brightness, _controller.value),
            ),
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

class _RainParticles extends StatefulWidget {
  const _RainParticles();

  @override
  State<_RainParticles> createState() => _RainParticlesState();
}

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

    for (int i = 0; i < 30; i++) {
      drops.add(Offset(random.nextDouble(), random.nextDouble()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return SizedBox.expand(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _RainPainter(drops, _controller.value),
            ),
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
