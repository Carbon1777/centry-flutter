import 'dart:async';

import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  final String nickname;

  /// Вызывается когда welcome-анимация завершена и можно показывать Feed.
  final VoidCallback? onWelcomeCompleted;

  const HomeScreen({
    super.key,
    required this.nickname,
    this.onWelcomeCompleted,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _iconOpacity;
  late final Animation<double> _iconScale;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _handRotation;
  late final Animation<double> _textOpacity;
  late final Animation<Offset> _textSlide;

  // Анимации для каждой буквы ника
  late final List<Animation<double>> _letterOpacities;
  late final List<Animation<double>> _letterScales;

  bool _committed = false;

  // Окно анимации ника: 0.46 – 0.68
  static const double _nickStart = 0.46;
  static const double _nickEnd   = 0.68;
  // Каждая буква анимируется за этот относительный отрезок окна
  static const double _letterDuration = 0.09;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5500),
    );

    // Иконка: первая — fade + scale
    _iconOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.10, curve: Curves.easeOut),
    );
    _iconScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.6, end: 1.08)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.08, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.14),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.26, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.12, 0.26, curve: Curves.easeOut),
    ));

    _handRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.35)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: -0.25)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.25, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.26, 0.46),
      ),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 0.90, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.68, 0.90, curve: Curves.easeOut),
    ));

    _buildLetterAnimations();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        unawaited(_commitAfterWelcome());
      }
    });

    _controller.forward();
  }

  void _buildLetterAnimations() {
    final chars = widget.nickname.split('');
    final n = chars.length;

    if (n == 0) {
      _letterOpacities = [];
      _letterScales = [];
      return;
    }

    // Шаг между стартами букв — равномерно делим окно
    final stagger = n > 1
        ? (_nickEnd - _nickStart - _letterDuration) / (n - 1)
        : 0.0;

    _letterOpacities = List.generate(n, (i) {
      final start = _nickStart + i * stagger;
      // Буква полностью проявляется за первую половину своего отрезка
      final fadeEnd = (start + _letterDuration * 0.45).clamp(0.0, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, fadeEnd, curve: Curves.easeOut),
      );
    });

    _letterScales = List.generate(n, (i) {
      final start = _nickStart + i * stagger;
      final end = (start + _letterDuration).clamp(0.0, 1.0);
      return TweenSequence<double>([
        // Растём от 0.5 до 1.22
        TweenSequenceItem(
          tween: Tween(begin: 0.5, end: 1.22)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40,
        ),
        // Возвращаемся в 1.0 — "садимся" на место
        TweenSequenceItem(
          tween: Tween(begin: 1.22, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 60,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end),
        ),
      );
    });
  }

  Future<void> _commitAfterWelcome() async {
    if (_committed || !mounted) return;
    _committed = true;

    // Даём фразе 500мс для фиксации в сознании
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    widget.onWelcomeCompleted?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.25),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Иконка приложения ──────────────────────────────
                  Opacity(
                    opacity: _iconOpacity.value,
                    child: Transform.scale(
                      scale: _iconScale.value,
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 117,
                        height: 117,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Добро пожаловать ───────────────────────────────
                  FadeTransition(
                    opacity: _titleOpacity,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Добро пожаловать',
                            style: TextStyle(
                              fontSize: 29,
                              fontWeight: FontWeight.w600,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Transform.rotate(
                            angle: _handRotation.value,
                            child: const Text(
                              '👋',
                              style: TextStyle(fontSize: 30),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (widget.nickname.trim().isNotEmpty &&
                      _letterOpacities.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(
                        widget.nickname.split('').length,
                        (i) => Opacity(
                          opacity: _letterOpacities[i].value,
                          child: Transform.scale(
                            scale: _letterScales[i].value,
                            child: Text(
                              widget.nickname.split('')[i],
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                height: 1.05,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FadeTransition(
                    opacity: _textOpacity,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Text(
                        'Посмотрим, что сегодня интересного…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.1,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
