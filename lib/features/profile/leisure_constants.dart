import 'package:flutter/material.dart';

class LeisureOption {
  final String key;
  final String emoji;
  final String label;
  final String subLabel;

  const LeisureOption(this.key, this.emoji, this.label, this.subLabel);

  /// Material-иконка взамен эмодзи. Эмодзи на iPad-симуляторе iOS 26.3
  /// рендерятся как `?` — Apple Color Emoji ненадёжен. Material Icons
  /// — векторный шрифт, гарантированно рисуется на любой платформе.
  IconData get icon => LeisureConstants.iconFor(key);
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

  /// Маппинг ключей LeisureOption на Material-иконки.
  /// См. комментарий в [LeisureOption.icon].
  static IconData iconFor(String key) {
    switch (key) {
      // restPreferences
      case 'rest_format_dining':       return Icons.restaurant;
      case 'rest_format_bars':         return Icons.local_bar;
      case 'rest_format_walks':        return Icons.park;
      case 'rest_format_loud':         return Icons.celebration;
      case 'rest_format_spontaneous':  return Icons.directions_car;
      case 'rest_format_leisure':      return Icons.movie;
      case 'rest_format_active':       return Icons.directions_run;

      // restDislikes
      case 'rest_dislike_noise':         return Icons.volume_up;
      case 'rest_dislike_late':          return Icons.schedule;
      case 'rest_dislike_alcohol':       return Icons.wine_bar;
      case 'rest_dislike_strict_plans':  return Icons.assignment;
      case 'rest_dislike_large_groups':  return Icons.groups;
      case 'rest_dislike_long_walks':    return Icons.directions_walk;
      case 'rest_dislike_spontaneous':   return Icons.bolt;

      // socialFormats
      case 'social_one_on_one':    return Icons.person;
      case 'social_small_group':   return Icons.group;
      case 'social_large_group':   return Icons.diversity_3;

      // restTempos
      case 'tempo_spontaneous':  return Icons.bolt;
      case 'tempo_planned':      return Icons.event;
      case 'tempo_flexible':     return Icons.balance;

      // meetingTimes
      case 'time_morning':       return Icons.wb_twilight;
      case 'time_afternoon':     return Icons.wb_sunny;
      case 'time_evening':       return Icons.brightness_3;
      case 'time_late_evening':  return Icons.bedtime;

      // vibes
      case 'vibe_calm':       return Icons.self_improvement;
      case 'vibe_easy':       return Icons.thumb_up_alt;
      case 'vibe_conscious':  return Icons.psychology;
      case 'vibe_energetic':  return Icons.local_fire_department;
      case 'vibe_mix':        return Icons.auto_awesome;

      default: return Icons.label_outline;
    }
  }
}
