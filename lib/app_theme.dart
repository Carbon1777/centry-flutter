import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData dark() {
    const Color background = Color(0xFF0F1115);
    const Color surface = Color(0xFF171A21);

    const Color primaryText = Color(0xFFE6E8EC);

    // 👇 стало чуть светлее — для пояснений и onboarding
    const Color secondaryText = Color(0xFFB3B8C4);

    const Color accent = Color(0xFF5B8DFF);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      cardColor: surface,

      colorScheme: const ColorScheme.dark(
        background: background,
        surface: surface,
        primary: accent,
        onPrimary: primaryText,
        onBackground: primaryText,
        onSurface: primaryText,
      ),

      // =======================
      // Text theme — КАНОН
      // =======================
      textTheme: const TextTheme(
        // Интро, заголовки экранов (Home, Permissions intro)
        titleLarge: TextStyle(
          color: primaryText,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),

        // Подзаголовки, секции (Геопозиция, Уведомления)
        titleMedium: TextStyle(
          color: primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),

        // Основной текст
        bodyMedium: TextStyle(
          color: primaryText,
          fontSize: 15,
        ),

        // Пояснения, описания, onboarding-тексты
        bodySmall: TextStyle(
          color: secondaryText,
          fontSize: 15,
          height: 1.4,
        ),

        // Вторичные действия: "Пропустить", хинты
        labelMedium: TextStyle(
          color: secondaryText,
          fontSize: 14,
        ),
      ),

      // =======================
      // AppBar
      // =======================
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: primaryText),
      ),

      // Иконки по умолчанию — вторичные
      iconTheme: const IconThemeData(color: secondaryText),
    );
  }
}
