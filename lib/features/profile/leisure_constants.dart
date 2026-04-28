import 'package:flutter/material.dart';

class LeisureOption {
  final String key;
  final String emoji;
  final String label;
  final String subLabel;

  const LeisureOption(this.key, this.emoji, this.label, this.subLabel);

  String get assetPath => LeisureConstants.assetPathFor(key);
}

class LeisureConstants {
  static const List<LeisureOption> restPreferences = [
    LeisureOption('rest_format_dining', '🍽', 'Рестораны и ужины', 'люблю спокойно посидеть и вкусно поесть'),
    LeisureOption('rest_format_bars', '🍸', 'Бары и вечерние встречи', 'люблю бары, коктейли и вечерний вайб'),
    LeisureOption('rest_format_walks', '🌿', 'Прогулки и спокойный отдых', 'люблю гулять, общаться и отдыхать без суеты'),
    LeisureOption('rest_format_loud', '🎉', 'Шумные компании и движ', 'люблю активные компании, веселье и много людей'),
    LeisureOption('rest_format_spontaneous', '🚗', 'Спонтанные выезды', 'люблю быстро собраться и куда-нибудь поехать'),
    LeisureOption('rest_format_leisure', '🎬', 'Неспешный досуг', 'люблю спокойные места и расслабленный ритм'),
    LeisureOption('rest_format_active', '🏃', 'Активный отдых', 'люблю активность, движение и не сидеть на месте'),
  ];

  static const List<LeisureOption> restDislikes = [
    LeisureOption('rest_dislike_noise', '🔊', 'Слишком шумные места', 'не люблю шум, громкую музыку и перегруз'),
    LeisureOption('rest_dislike_late', '🕐', 'Поздние встречи', 'не люблю поздние сборы и ночной формат'),
    LeisureOption('rest_dislike_alcohol', '🍷', 'Алкогольный формат', 'не люблю отдых, завязанный на алкоголе'),
    LeisureOption('rest_dislike_strict_plans', '📋', 'Жесткие планы', 'не люблю, когда всё слишком строго расписано'),
    LeisureOption('rest_dislike_large_groups', '👥', 'Большие компании', 'не люблю слишком много людей сразу'),
    LeisureOption('rest_dislike_long_walks', '🚶', 'Долгие прогулки', 'не люблю долгие пешие маршруты'),
    LeisureOption('rest_dislike_spontaneous', '⚡', 'Спонтанность', 'не люблю собираться в последний момент'),
  ];

  static const List<LeisureOption> socialFormats = [
    LeisureOption('social_one_on_one', '👤', 'Один на один', 'комфортнее общаться тет-а-тет'),
    LeisureOption('social_small_group', '👥', 'Небольшая компания', 'комфортнее 2–5 человек'),
    LeisureOption('social_large_group', '🧑‍🤝‍🧑', 'Компания побольше', 'люблю более живые и большие компании'),
  ];

  static const List<LeisureOption> restTempos = [
    LeisureOption('tempo_spontaneous', '⚡', 'Спонтанный', 'могу быстро сорваться и поехать'),
    LeisureOption('tempo_planned', '🗓', 'Планирую заранее', 'комфортнее договориться заранее'),
    LeisureOption('tempo_flexible', '⚖️', 'Гибкий', 'могу и спонтанно, и по плану'),
  ];

  static const List<LeisureOption> meetingTimes = [
    LeisureOption('time_morning', '🌅', 'Утром', ''),
    LeisureOption('time_afternoon', '☀️', 'Днём', ''),
    LeisureOption('time_evening', '🌇', 'Вечером', ''),
    LeisureOption('time_late_evening', '🌙', 'Поздно вечером', ''),
  ];

  static const List<LeisureOption> vibes = [
    LeisureOption('vibe_calm', '😌', 'Спокойный', 'люблю комфорт, легкость и без напряга'),
    LeisureOption('vibe_easy', '😎', 'Лёгкий на подъём', 'люблю быстро собраться и не усложнять'),
    LeisureOption('vibe_conscious', '🧠', 'Осознанный', 'люблю содержательное общение и хороший вайб'),
    LeisureOption('vibe_energetic', '🔥', 'Энергичный', 'люблю движение, эмоции и насыщенный отдых'),
    LeisureOption('vibe_mix', '✨', 'Микс', 'всё зависит от настроения и компании'),
  ];

  static LeisureOption? findByKey(List<LeisureOption> options, String key) {
    for (final o in options) {
      if (o.key == key) return o;
    }
    return null;
  }

  // Маппинг key → twemoji asset (CC-BY 4.0). Apple Color Emoji ненадёжен на
  // iPad-симуляторе iOS 26.3, потому используем bundled Twemoji PNG.
  static String assetPathFor(String key) {
    switch (key) {
      // restPreferences
      case 'rest_format_dining':       return 'assets/twemoji/1f37d.png';
      case 'rest_format_bars':         return 'assets/twemoji/1f378.png';
      case 'rest_format_walks':        return 'assets/twemoji/1f33f.png';
      case 'rest_format_loud':         return 'assets/twemoji/1f389.png';
      case 'rest_format_spontaneous':  return 'assets/twemoji/1f697.png';
      case 'rest_format_leisure':      return 'assets/twemoji/1f3ac.png';
      case 'rest_format_active':       return 'assets/twemoji/1f3c3.png';

      // restDislikes
      case 'rest_dislike_noise':         return 'assets/twemoji/1f50a.png';
      case 'rest_dislike_late':          return 'assets/twemoji/1f550.png';
      case 'rest_dislike_alcohol':       return 'assets/twemoji/1f377.png';
      case 'rest_dislike_strict_plans':  return 'assets/twemoji/1f4cb.png';
      case 'rest_dislike_large_groups':  return 'assets/twemoji/1f465.png';
      case 'rest_dislike_long_walks':    return 'assets/twemoji/1f6b6.png';
      case 'rest_dislike_spontaneous':   return 'assets/twemoji/26a1.png';

      // socialFormats
      case 'social_one_on_one':    return 'assets/twemoji/1f464.png';
      case 'social_small_group':   return 'assets/twemoji/1f465.png';
      case 'social_large_group':   return 'assets/twemoji/1f9d1-200d-1f91d-200d-1f9d1.png';

      // restTempos
      case 'tempo_spontaneous':  return 'assets/twemoji/26a1.png';
      case 'tempo_planned':      return 'assets/twemoji/1f5d3.png';
      case 'tempo_flexible':     return 'assets/twemoji/2696.png';

      // meetingTimes
      case 'time_morning':       return 'assets/twemoji/1f305.png';
      case 'time_afternoon':     return 'assets/twemoji/2600.png';
      case 'time_evening':       return 'assets/twemoji/1f307.png';
      case 'time_late_evening':  return 'assets/twemoji/1f319.png';

      // vibes
      case 'vibe_calm':       return 'assets/twemoji/1f60c.png';
      case 'vibe_easy':       return 'assets/twemoji/1f60e.png';
      case 'vibe_conscious':  return 'assets/twemoji/1f9e0.png';
      case 'vibe_energetic':  return 'assets/twemoji/1f525.png';
      case 'vibe_mix':        return 'assets/twemoji/2728.png';

      default: return 'assets/twemoji/2728.png';
    }
  }
}

class TwemojiIcon extends StatelessWidget {
  final String assetPath;
  final double size;

  const TwemojiIcon({
    super.key,
    required this.assetPath,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}
