import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/analytics/analytics_service.dart';
import '../../core/analytics/screen_analytics_mixin.dart';

/// Запрос системных разрешений (геолокация + уведомления) ОДНИМ экраном.
///
/// Экран показывается сразу после AgreementScreen, до AuthScreen.
/// Per-device, не per-account: запрашивается один раз на устройстве.
///
/// При нажатии "Продолжить" подряд показываются ДВА системных диалога iOS/Android:
/// сначала location, затем notifications. Никакого exit-button нет —
/// пользователь не может пропустить запрос (Apple Guideline 5.1.1(iv)).
class PermissionsScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const PermissionsScreen({
    super.key,
    required this.onContinue,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with ScreenAnalyticsMixin<PermissionsScreen> {
  bool _loading = false;

  @override
  String get screenName => 'permissions';

  @override
  void initState() {
    super.initState();
    AnalyticsService.event(AppEvents.permissionsShown);
  }

  Future<void> _onContinue() async {
    if (_loading) return;
    setState(() => _loading = true);

    bool locationGranted = false;
    bool notificationsGranted = false;

    // 1) Location — системный диалог iOS/Android.
    // Если permission уже определён, requestPermission вернёт текущий статус
    // мгновенно и без диалога — это ок, идём дальше.
    try {
      final perm = await Geolocator.requestPermission();
      locationGranted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (_) {
      // Игнорируем — отсутствие разрешения не блокирует онбординг,
      // приложение работает по выбранному в аккаунте городу.
    }

    if (!mounted) return;

    // 2) Notifications — FirebaseMessaging.requestPermission на iOS вызывает
    // родной UNUserNotificationCenter.requestAuthorization. Маленькая пауза,
    // чтобы предыдущий системный диалог гео успел полностью закрыться,
    // иначе iOS может проигнорировать второй запрос.
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      notificationsGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      // Пуши не критичны для запуска, отказ не блокирует онбординг.
    }

    final anyGranted = locationGranted || notificationsGranted;
    AnalyticsService.event(
      anyGranted ? AppEvents.permissionsGranted : AppEvents.permissionsSkipped,
      {
        'location': locationGranted,
        'notifications': notificationsGranted,
      },
    );

    if (!mounted) return;

    setState(() => _loading = false);
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Для полноценной работы приложения нам нужны два разрешения',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 32),
              _PermissionRow(
                icon: Icons.location_on_outlined,
                title: 'Геопозиция',
                description:
                    'Чтобы показывать на карте заведения и события рядом с вами — например, бары и рестораны поблизости. Без доступа карта откроется по центру выбранного города.',
                colors: colors,
                theme: theme,
              ),
              const SizedBox(height: 24),
              _PermissionRow(
                icon: Icons.notifications_outlined,
                title: 'Уведомления',
                description:
                    'Чтобы вовремя сообщать о приглашениях друзей, новых сообщениях в чатах и событиях, на которые вы записаны.',
                colors: colors,
                theme: theme,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _onContinue,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Продолжить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final ColorScheme colors;
  final ThemeData theme;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
