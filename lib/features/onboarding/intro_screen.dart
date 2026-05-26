import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/analytics/analytics_service.dart';

/// Стартовый слайд при первом запуске. Показывается ОДИН раз.
/// Переход — только по кнопке «Далее»: авто-таймера нет, юзер сам читает.
///
/// Ключ SharedPreferences (`intro_video_seen`) сохранён от предыдущего
/// video-варианта намеренно: юзеры, прошедшие старый ролик, не увидят слайд.
class IntroScreen extends StatefulWidget {
  final VoidCallback onDone;

  const IntroScreen({super.key, required this.onDone});

  static const _kSeenKey = 'intro_video_seen';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kSeenKey) ?? false);
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenKey, true);
  }

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.event(AppEvents.introShown);
  }

  Future<void> _finish() async {
    if (_done) return;
    _done = true;
    AnalyticsService.event(AppEvents.introDismissedTap);
    await IntroScreen.markSeen();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 128,
                  height: 128,
                ),
              ),
              const SizedBox(height: 36),
              const Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: Color(0xFFE6E8EC),
                    fontSize: 17,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(text: 'Инструкции по функционалу приложения\nесть на сайте '),
                    TextSpan(
                      text: 'centryweb.ru',
                      style: TextStyle(
                        color: Color(0xFF5B8DFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: '.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                'Заблудишься — приходи!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE6E8EC),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _finish,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B8DFF),
                    foregroundColor: const Color(0xFFE6E8EC),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Далее',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
