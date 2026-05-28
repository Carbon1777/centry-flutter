import 'package:appmetrica_plugin/appmetrica_plugin.dart';
import 'package:flutter/foundation.dart';

import '../../config/appmetrica_keys.dart';

/// Точки отвала в онбординге Centry. Передавать в [AnalyticsService.event].
class AppEvents {
  // App lifecycle
  static const appOpen = 'app_open';

  // Onboarding funnel
  static const introShown = 'intro_shown';
  static const introDismissedTap = 'intro_dismissed_tap';

  static const agreementShown = 'agreement_shown';
  static const agreementAccepted = 'agreement_accepted';

  static const nicknameShown = 'nickname_shown';
  static const nicknameSubmitted = 'nickname_submitted';

  static const permissionsShown = 'permissions_shown';
  static const permissionsGranted = 'permissions_granted';
  static const permissionsSkipped = 'permissions_skipped';

  // Email / sign-up funnel
  static const emailFormShown = 'email_form_shown';
  static const emailSubmitted = 'email_submitted';
  static const emailConfirmed = 'email_confirmed';
}

/// Обёртка над AppMetrica. Безопасна к двойной инициализации и к отсутствию ключа.
class AnalyticsService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      await AppMetrica.activate(
        const AppMetricaConfig(AppMetricaKeys.apiKey),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('[Analytics] init failed: $e');
    }
  }

  static void event(String name, [Map<String, Object>? params]) {
    if (kIsWeb) return;
    try {
      if (params == null) {
        AppMetrica.reportEvent(name);
      } else {
        AppMetrica.reportEventWithMap(name, params);
      }
    } catch (e) {
      debugPrint('[Analytics] event "$name" failed: $e');
    }
  }

  /// Связывает текущий device_id AppMetrica с канонический ID юзера Centry
  /// (`app_user_id`, не `auth.uid()` — см. server-first принцип в CLAUDE.md).
  /// После этого фильтрация воронки по конкретному юзеру работает в UI AppMetrica.
  static void setUserId(String userId) {
    if (kIsWeb) return;
    if (userId.isEmpty) return;
    try {
      AppMetrica.setUserProfileID(userId);
    } catch (e) {
      debugPrint('[Analytics] setUserId failed: $e');
    }
  }

  /// Отвязывает device_id от юзера (на signOut). Следующие события
  /// будут трекаться без user profile id, пока не вызовется setUserId.
  static void clearUserId() {
    if (kIsWeb) return;
    try {
      AppMetrica.setUserProfileID(null);
    } catch (e) {
      debugPrint('[Analytics] clearUserId failed: $e');
    }
  }
}
