import 'package:flutter/widgets.dart';

import 'analytics_service.dart';

/// Подмешать в State экрана, который надо мерить.
/// На initState отправляет `screen_view {screen: <name>}`, на dispose —
/// `screen_close {screen: <name>, duration_ms: N}`.
///
/// Использование:
/// ```
/// class _MyScreenState extends State<MyScreen> with ScreenAnalyticsMixin<MyScreen> {
///   @override String get screenName => 'my_screen';
///   ...
/// }
/// ```
mixin ScreenAnalyticsMixin<T extends StatefulWidget> on State<T> {
  /// Канонический snake_case-идентификатор экрана.
  /// Используется как `screen` атрибут в событиях `screen_view`/`screen_close`.
  String get screenName;

  DateTime? _screenEnteredAt;

  @override
  void initState() {
    super.initState();
    _screenEnteredAt = DateTime.now();
    AnalyticsService.event('screen_view', {'screen': screenName});
  }

  @override
  void dispose() {
    final entered = _screenEnteredAt;
    if (entered != null) {
      final ms = DateTime.now().difference(entered).inMilliseconds;
      AnalyticsService.event('screen_close', {
        'screen': screenName,
        'duration_ms': ms,
      });
    }
    super.dispose();
  }
}
