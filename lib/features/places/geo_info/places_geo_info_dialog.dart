import 'dart:async';

import 'package:flutter/material.dart';

class PlacesGeoInfoDialog extends StatefulWidget {
  final String text;
  final VoidCallback onNeverShow;

  /// ===========================================================
  /// SESSION FLAG
  /// Диалог может быть показан только ОДИН раз
  /// за жизненный цикл приложения (пока не убито).
  /// ===========================================================

  static bool _shownThisSession = false;

  /// Проверка перед показом (вызывается СНАРУЖИ)
  static bool canShowThisSession() => !_shownThisSession;

  /// Помечаем, что диалог уже был показан в этой сессии
  static void markShownForSession() {
    _shownThisSession = true;
  }

  const PlacesGeoInfoDialog({
    super.key,
    required this.text,
    required this.onNeverShow,
  });

  @override
  State<PlacesGeoInfoDialog> createState() => _PlacesGeoInfoDialogState();
}

class _PlacesGeoInfoDialogState extends State<PlacesGeoInfoDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // ✅ фиксируем факт показа НА СЕССИЮ
    PlacesGeoInfoDialog.markShownForSession();

    _timer = Timer(const Duration(seconds: 7), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Dismissible(
      key: const ValueKey('places_geo_info_dialog'),
      direction: DismissDirection.horizontal, // ⬅️➡️ свайп влево / вправо
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.text,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // ❌ перманентный запрет (storage / controller)
                    widget.onNeverShow();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Не показывать'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
