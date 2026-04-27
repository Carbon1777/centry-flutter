import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/feed/feed_place_dto.dart';
import '../../common/category_placeholder.dart';

// Цвета сигналов
const _kColorPlanned    = Color(0xFF2E7D32); // зелёный — идут
const _kColorInterested = Color(0xFF5C6BC0); // индиго — интересуются
const _kColorVisited    = Color(0xFF607D8B); // серо-синий — были

class FeedPlaceCard extends StatelessWidget {
  final FeedPlaceDto place;
  final VoidCallback onTap;

  const FeedPlaceCard({
    super.key,
    required this.place,
    required this.onTap,
  });

  String? get _distanceLabel {
    final d = place.distanceMeters;
    if (d == null) return null;
    if (d < 1000) return '$d м от вас';
    final km = d / 1000;
    return '${km.toStringAsFixed(km < 10 ? 2 : 1)} км от вас';
  }

  Color get _distanceColor {
    final d = place.distanceMeters;
    if (d == null) return Colors.transparent;
    if (d < 1000) return const Color(0xFF2E7D32);
    if (d < 5000) return const Color.fromARGB(255, 241, 241, 8);
    if (d < 10000) return const Color(0xFFEF6C00);
    return const Color(0xFFC62828);
  }

  /// Цвет левой полоски — по приоритету фазы сигнала.
  Color? get _accentBarColor {
    if (place.plannedCount > 0)    return _kColorPlanned;
    if (place.interestedCount > 0) return _kColorInterested;
    if (place.visitedCount > 0)    return _kColorVisited;
    return null; // нет активности — нет полоски
  }


  String get _categoryLabel {
    switch (place.category) {
      case 'restaurant': return 'Ресторан';
      case 'bar':        return 'Бар';
      case 'nightclub':  return 'Ночной клуб';
      case 'cinema':     return 'Кинотеатр';
      case 'theatre':    return 'Театр';
      case 'karaoke':    return 'Кaраоке';
      case 'hookah':     return 'Кальянная';
      case 'bathhouse':  return 'Баня / Сауна';
      default:           return place.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardRadius = BorderRadius.circular(16);
    final textTheme  = Theme.of(context).textTheme;
    final colors     = Theme.of(context).colorScheme;
    final barColor   = _accentBarColor;

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: cardRadius,
      child: InkWell(
        borderRadius: cardRadius,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: cardRadius,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Левая акцентная полоска ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: barColor != null ? 4 : 0,
                  color: barColor,
                ),

                // ── Основной контент ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Фото + рейтинг
                        SizedBox(
                          width: 88,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade800,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _PlacePhoto(
                                    storageKey: place.photoStorageKey,
                                    category: place.category,
                                    placeId: place.placeId,
                                  ),
                                ),
                              ),
                              if (place.rating != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 2),
                                    Text(
                                      place.rating!.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Текстовый блок
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                place.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _categoryLabel,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              if (_distanceLabel != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  _distanceLabel!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _distanceColor,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                              // Два блока в одну строку, выровнены по верху
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ЛЕВЫЙ блок: метро → планы → история (без пропусков)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (place.metroName != null) ...[
                                          Text(
                                            'м.${place.metroName}'
                                            '${place.metroDistanceMeters != null ? " · ${place.metroDistanceMeters} м" : ""}',
                                            style: textTheme.bodySmall?.copyWith(
                                                color: Colors.grey.shade500),
                                          ),
                                          const SizedBox(height: 3),
                                        ],
                                        _PlansBadge(
                                          count: place.countPlans,
                                          colors: colors,
                                        ),
                                        if (place.pastPlansCount > 0) ...[
                                          const SizedBox(height: 3),
                                          _PastPlansBadge(count: place.pastPlansCount),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // ПРАВЫЙ блок: сигналы один под одним (без пропусков)
                                  if (place.plannedCount > 0 ||
                                      place.interestedCount > 0 ||
                                      place.visitedCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (place.plannedCount > 0)
                                            _SignalChip(
                                              icon: Icons.directions_walk,
                                              label: '${place.plannedCount} идут',
                                              color: _kColorPlanned,
                                            ),
                                          if (place.interestedCount > 0) ...[
                                            const SizedBox(height: 3),
                                            _SignalChip(
                                              icon: Icons.visibility_outlined,
                                              label: '${place.interestedCount} интерес.',
                                              color: _kColorInterested,
                                            ),
                                          ],
                                          if (place.visitedCount > 0) ...[
                                            const SizedBox(height: 3),
                                            _SignalChip(
                                              icon: Icons.check_circle_outline,
                                              label: '${place.visitedCount} были',
                                              color: _kColorVisited,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Бейдж активных планов ─────────────────────────────────
class _PlansBadge extends StatelessWidget {
  final int count;
  final ColorScheme colors;

  const _PlansBadge({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: active ? colors.primary.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active
            ? Border.all(color: colors.primary.withValues(alpha: 0.35), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_note_outlined,
              size: 12,
              color: active ? colors.primary : Colors.grey.shade600),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Планов — $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? colors.primary : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Бейдж истории планов ──────────────────────────────────
class _PastPlansBadge extends StatelessWidget {
  final int count;

  const _PastPlansBadge({required this.count});

  static String _label(int n) {
    final word = n == 1 ? 'плане' : 'планах';
    return 'Было в $n $word';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.history, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            _label(count),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Фото места ────────────────────────────────────────────
class _PlacePhoto extends StatelessWidget {
  final String? storageKey;
  final String category;
  final String placeId;

  const _PlacePhoto({
    required this.storageKey,
    required this.category,
    required this.placeId,
  });

  @override
  Widget build(BuildContext context) {
    final catUrl = categoryPlaceholderUrl(category, placeId);

    Widget fallback() => catUrl != null
        ? Image.network(
            catUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/place_placeholder.png',
              fit: BoxFit.cover,
            ),
          )
        : Image.asset('assets/images/place_placeholder.png',
            fit: BoxFit.cover);

    final key = storageKey;
    if (key != null && key.isNotEmpty) {
      final url = Supabase.instance.client.storage
          .from('brand-media')
          .getPublicUrl(key);
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return fallback();
  }
}

class _SignalChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SignalChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
