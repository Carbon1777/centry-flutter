import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:store_checker/store_checker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Определяет магазин, из которого установлено приложение, и пишет
/// атрибуцию в `app_users.install_store` один раз на юзера.
///
/// Поведение:
///   • `detect()` — на старте приложения. Кэширует результат в SharedPreferences
///     и в статике класса, чтобы не дёргать platform-channel повторно.
///   • `persistForUser(appUserId)` — после успешной авторизации. Пишет в БД
///     только если поле сейчас NULL (server-side фильтр по `is.null`), чтобы
///     не перетереть атрибуцию более раннего билда.
///
/// Канонический ID юзера в Centry — `app_user_id` (а не `auth.uid()`,
/// см. CLAUDE.md и server-first принцип). Поэтому persistForUser принимает
/// именно app_user_id и пишет `where id = appUserId`.
class InstallSourceService {
  static const String _prefsKey = 'install_store_v1';

  /// Allowed values for app_users.install_store CHECK constraint.
  static const Set<String> _allowedValues = {
    'app_store',
    'google_play',
    'rustore',
    'huawei',
    'samsung',
    'amazon',
    'sideload',
    'unknown',
  };

  static String? _cached;

  /// Возвращает строку из словаря CHECK или null на web (где детект невозможен).
  /// Идемпотентно: повторные вызовы отдают закэшированное значение.
  static Future<String?> detect() async {
    if (kIsWeb) return null;
    if (_cached != null) return _cached;

    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored != null && _allowedValues.contains(stored)) {
        _cached = stored;
        return stored;
      }

      final source = await StoreChecker.getSource;
      final normalized = _normalize(source);

      _cached = normalized;
      await prefs.setString(_prefsKey, normalized);
      return normalized;
    } catch (e) {
      debugPrint('[InstallSource] detect failed: $e');
      return null;
    }
  }

  /// Записывает install_store в app_users только если поле сейчас NULL.
  /// Не пробрасывает ошибки — это side-effect аналитики, не должен ломать UX.
  static Future<void> persistForUser(String appUserId) async {
    if (kIsWeb) return;
    if (appUserId.isEmpty) return;

    final value = await detect();
    if (value == null) return;

    try {
      await Supabase.instance.client
          .from('app_users')
          .update({'install_store': value})
          .eq('id', appUserId)
          .isFilter('install_store', null);
    } catch (e) {
      debugPrint('[InstallSource] persistForUser failed: $e');
    }
  }

  static String _normalize(Source source) {
    switch (source) {
      case Source.IS_INSTALLED_FROM_PLAY_STORE:
        return 'google_play';
      case Source.IS_INSTALLED_FROM_PLAY_PACKAGE_INSTALLER:
        return 'google_play';
      case Source.IS_INSTALLED_FROM_APP_STORE:
        return 'app_store';
      case Source.IS_INSTALLED_FROM_TEST_FLIGHT:
        return 'app_store';
      case Source.IS_INSTALLED_FROM_RU_STORE:
        return 'rustore';
      case Source.IS_INSTALLED_FROM_HUAWEI_APP_GALLERY:
        return 'huawei';
      case Source.IS_INSTALLED_FROM_SAMSUNG_GALAXY_STORE:
        return 'samsung';
      case Source.IS_INSTALLED_FROM_SAMSUNG_SMART_SWITCH_MOBILE:
        return 'samsung';
      case Source.IS_INSTALLED_FROM_AMAZON_APP_STORE:
        return 'amazon';
      case Source.IS_INSTALLED_FROM_LOCAL_SOURCE:
        return 'sideload';
      case Source.IS_INSTALLED_FROM_OTHER_SOURCE:
        return 'unknown';
      case Source.UNKNOWN:
        return 'unknown';
      // Если store_checker расширит enum в новой версии — fallback на unknown,
      // чтобы клиент не падал и значение проходило CHECK.
      // ignore: unreachable_switch_default
      default:
        return 'unknown';
    }
  }
}
