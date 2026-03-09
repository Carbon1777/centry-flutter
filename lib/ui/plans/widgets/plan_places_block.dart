import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/plans/plan_details_dto.dart';

class PlanPlacesBlock extends StatelessWidget {
  final List<PlaceCandidateDto> items;
  final VoidCallback? onAddCandidate;
  final bool actionsDisabled;
  final ValueChanged<PlaceCandidateDto>? onOpenDetails;
  final ValueChanged<PlaceCandidateDto>? onOpenOnMap;
  final ValueChanged<PlaceCandidateDto>? onRemoveCandidate;

  const PlanPlacesBlock({
    super.key,
    required this.items,
    this.onAddCandidate,
    this.actionsDisabled = false,
    this.onOpenDetails,
    this.onOpenOnMap,
    this.onRemoveCandidate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAdd = onAddCandidate != null && !actionsDisabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Кандидаты',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                onPressed: canAdd ? onAddCandidate : null,
                tooltip: 'Добавить место',
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.dividerColor.withOpacity(0.22),
              ),
            ),
            child: Text(
              'Нет мест',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
            ),
          )
        else
          SizedBox(
            height: math.min(
              items.length * 108.0 + ((items.length - 1) * 8.0),
              560.0,
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];

                if (item.isCorePlace) {
                  return _CoreCandidateCard(
                    item: item,
                    actionsDisabled: actionsDisabled,
                    onOpenDetails: onOpenDetails == null
                        ? null
                        : () => onOpenDetails!(item),
                    onOpenOnMap:
                        onOpenOnMap == null ? null : () => onOpenOnMap!(item),
                    onRemove: item.canDelete &&
                            onRemoveCandidate != null &&
                            !actionsDisabled
                        ? () => onRemoveCandidate!(item)
                        : null,
                  );
                }

                return _SubmissionCandidateCard(
                  item: item,
                  actionsDisabled: actionsDisabled,
                  onOpenDetails:
                      onOpenDetails == null ? null : () => onOpenDetails!(item),
                  onRemove: item.canDelete &&
                          onRemoveCandidate != null &&
                          !actionsDisabled
                      ? () => onRemoveCandidate!(item)
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _CoreCandidateCard extends StatelessWidget {
  final PlaceCandidateDto item;
  final bool actionsDisabled;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenOnMap;
  final VoidCallback? onRemove;

  const _CoreCandidateCard({
    required this.item,
    required this.actionsDisabled,
    this.onOpenDetails,
    this.onOpenOnMap,
    this.onRemove,
  });

  String _typeLabel(String type) {
    switch (type) {
      case 'restaurant':
        return 'Ресторан';
      case 'bar':
        return 'Бар';
      case 'nightclub':
        return 'Ночной клуб';
      case 'cinema':
        return 'Кинотеатр';
      case 'theatre':
        return 'Театр';
      default:
        return 'Место';
    }
  }

  String? _distanceLabel(double? distanceM) {
    if (distanceM == null) return null;

    if (distanceM < 1000) {
      return '${distanceM.round()} м от вас';
    }

    final km = distanceM / 1000;
    final digits = km < 10 ? 2 : 1;
    return '${km.toStringAsFixed(digits)} км от вас';
  }

  Color _distanceColor(double? distanceM) {
    if (distanceM == null) return Colors.transparent;

    if (distanceM < 1000) {
      return const Color(0xFF2E7D32);
    } else if (distanceM < 5000) {
      return const Color.fromARGB(255, 241, 241, 8);
    } else if (distanceM < 10000) {
      return const Color(0xFFEF6C00);
    } else {
      return const Color(0xFFC62828);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compactTextButtonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );

    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          height: 1.05,
        );

    final distanceLabel = _distanceLabel(item.distanceM);

    return Stack(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Builder(
                            builder: (_) {
                              final url = item.previewMediaUrl;

                              if (url != null && url.isNotEmpty) {
                                return Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Image.asset(
                                      'assets/images/place_placeholder.png',
                                      fit: BoxFit.cover,
                                    );
                                  },
                                );
                              }

                              final key = item.previewStorageKey;
                              if (key != null && key.isNotEmpty) {
                                final publicUrl = Supabase
                                    .instance.client.storage
                                    .from('brand-media')
                                    .getPublicUrl(key);

                                return Image.network(
                                  publicUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Image.asset(
                                      'assets/images/place_placeholder.png',
                                      fit: BoxFit.cover,
                                    );
                                  },
                                );
                              }

                              return Image.asset(
                                'assets/images/place_placeholder.png',
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (item.rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          TextButton(
                            style: compactTextButtonStyle,
                            onPressed: actionsDisabled ? null : onOpenOnMap,
                            child: Text(
                              'Посмотреть\nна карте',
                              textAlign: TextAlign.right,
                              style: linkStyle,
                            ),
                          ),
                        ],
                      ),
                      if (distanceLabel != null)
                        Text(
                          distanceLabel,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _distanceColor(item.distanceM),
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                  ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        _typeLabel(item.type),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.areaName != null
                            ? '${item.cityName} · ${item.areaName}'
                            : item.cityName,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: item.metroName != null
                                ? Text(
                                    'м.${item.metroName}'
                                    '${item.metroDistanceM != null ? " · ${item.metroDistanceM} м" : ""}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.grey.shade500),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            style: compactTextButtonStyle,
                            onPressed: actionsDisabled ? null : onOpenDetails,
                            child: const Text('Подробнее'),
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
        if (onRemove != null)
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.red.withOpacity(0.9),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubmissionCandidateCard extends StatelessWidget {
  final PlaceCandidateDto item;
  final bool actionsDisabled;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onRemove;

  const _SubmissionCandidateCard({
    required this.item,
    required this.actionsDisabled,
    this.onOpenDetails,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/images/place_placeholder.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (onRemove != null)
                      Material(
                        color: Colors.red.withOpacity(0.9),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onRemove,
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.type,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  item.cityName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Голосов: ${item.votesCount}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: actionsDisabled ? null : onOpenDetails,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity:
                            const VisualDensity(horizontal: -2, vertical: -2),
                      ),
                      child: const Text('Подробнее'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
