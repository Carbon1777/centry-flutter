import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/geo/geo_service.dart';

/// Модалка геолокации для ленты.
///
/// Показывается ТОЛЬКО когда разрешение на гео не дано.
/// Дизайн аналогичен PlacesGeoInfoDialog.
class FeedGeoDialog extends StatefulWidget {
  /// Вызывается когда пользователь дал разрешение → лента перезагружается.
  final VoidCallback onPermissionGranted;

  /// Вызывается при нажатии "Больше не показывать" → флаг сохраняется в prefs.
  final VoidCallback onNeverShow;

  // ───────────── session flag ─────────────
  static bool _shownThisSession = false;
  static bool canShowThisSession() => !_shownThisSession;
  static void _markShownForSession() => _shownThisSession = true;
  // ────────────────────────────────────────

  static const _prefsKey = 'feed_geo_dialog_never_show';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_prefsKey) ?? false);
  }

  static Future<void> markNeverShow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, true);
  }

  const FeedGeoDialog({
    super.key,
    required this.onPermissionGranted,
    required this.onNeverShow,
  });

  @override
  State<FeedGeoDialog> createState() => _FeedGeoDialogState();
}

class _FeedGeoDialogState extends State<FeedGeoDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    FeedGeoDialog._markShownForSession();
    // Автозакрытие через 7 секунд (как у PlacesGeoInfoDialog)
    _timer = Timer(const Duration(seconds: 7), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onGivePermission() async {
    Navigator.of(context).pop();
    final permission = await Geolocator.requestPermission();
    final granted = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
    if (granted) {
      // Запрашиваем актуальную позицию сразу после выдачи разрешения
      await GeoService.instance.refresh();
      widget.onPermissionGranted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Dismissible(
      key: const ValueKey('feed_geo_dialog'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 44, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Лента построена случайным образом, так как вы не предоставили доступ к геолокации. Мы можем персонализировать её специально для вас.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _onGivePermission,
                      child: const Text('Дать разрешение'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: textTheme.bodySmall,
                      ),
                      onPressed: () {
                        widget.onNeverShow();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Больше не показывать'),
                    ),
                  ),
                ],
              ),
            ),
            // Крестик — закрыть (показать снова при следующем запуске)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
