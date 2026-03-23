import 'package:flutter/foundation.dart';

/// Singleton-шина состояния входящих знаков внимания.
/// Обновляется из:
///   • FCM foreground (ATTENTION_SIGN_RECEIVED)
///   • _BottomNavigationBar._loadBadges() — polling
///   • AttentionSignBoxScreen при открытии — сброс
class AttentionSignsBus {
  AttentionSignsBus._();
  static final instance = AttentionSignsBus._();

  final ValueNotifier<bool> hasIncoming = ValueNotifier(false);

  void setHasIncoming(bool value) {
    if (hasIncoming.value != value) {
      hasIncoming.value = value;
    }
  }
}
