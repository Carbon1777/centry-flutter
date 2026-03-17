import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpinningLogo extends StatefulWidget {
  final double size;
  final Duration duration;
  final double opacity;

  const SpinningLogo({
    super.key,
    this.size = 156.0,
    this.duration = const Duration(seconds: 5),
    this.opacity = 1.0,
  });

  @override
  State<SpinningLogo> createState() => _SpinningLogoState();
}

class _SpinningLogoState extends State<SpinningLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    const layers = 10;
    const thickness = 14.0;

    return Opacity(
      opacity: widget.opacity,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final angle = _ctrl.value * 2 * math.pi;
          final cosA = math.cos(angle);
          final sinA = math.sin(angle);

          final edgeVisibility = sinA.abs();
          final faceOpacity = (cosA.abs() * 0.6 + 0.4).clamp(0.0, 1.0);
          final glowOpacity = (cosA.abs() * 0.18).clamp(0.0, 1.0);
          final edgeDir = sinA > 0 ? -1.0 : 1.0;

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // статичное свечение под иконкой
              Container(
                width: size * 0.65,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B3FE4).withValues(alpha: 0.5),
                      blurRadius: 32,
                      spreadRadius: 6,
                    ),
                  ],
                ),
              ),

              // слои кромки
              for (int i = layers; i >= 1; i--)
                Transform.translate(
                  offset: Offset(
                    edgeDir * (thickness / layers) * i * edgeVisibility,
                    0,
                  ),
                  child: Opacity(
                    opacity: (1.0 - i / layers) * 0.55 * edgeVisibility,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0008)
                        ..rotateY(angle),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          const Color(0xFFFFD700).withValues(alpha: 0.6),
                          BlendMode.srcATop,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ),

              // лицевая сторона
              Opacity(
                opacity: faceOpacity,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0008)
                    ..rotateY(angle),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      child!,
                      if (glowOpacity > 0.01)
                        Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(size / 2),
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: glowOpacity),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.65],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        child: Image.asset(
          'assets/images/app_icon.png',
          width: size,
          height: size,
        ),
      ),
    );
  }
}
