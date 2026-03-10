import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/geo/geo_service.dart';
import '../../../data/plans/plan_details_dto.dart';

const double _candidateCardContentLockDelta = 86.0;
const int _candidateSlotsCount = 5;

class PlanPlacesBlock extends StatelessWidget {
  final List<PlaceCandidateDto> items;
  final VoidCallback? onAddCandidate;
  final bool actionsDisabled;
  final ValueChanged<PlaceCandidateDto>? onOpenDetails;
  final ValueChanged<PlaceCandidateDto>? onRemoveCandidate;

  const PlanPlacesBlock({
    super.key,
    required this.items,
    this.onAddCandidate,
    this.actionsDisabled = false,
    this.onOpenDetails,
    this.onRemoveCandidate,
  });

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(_candidateSlotsCount).toList();
    final canAdd = onAddCandidate != null && !actionsDisabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Кандидаты',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            primary: false,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _candidateSlotsCount,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index >= visibleItems.length) {
                return _AddCandidateSlot(
                  enabled: canAdd,
                  onTap: canAdd ? onAddCandidate : null,
                );
              }

              final item = visibleItems[index];

              if (item.isCorePlace) {
                return _CoreCandidateCard(
                  item: item,
                  actionsDisabled: actionsDisabled,
                  onTap:
                      onOpenDetails == null ? null : () => onOpenDetails!(item),
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
                onTap:
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

class _AddCandidateSlot extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _AddCandidateSlot({
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = BorderRadius.circular(16);
    final borderColor = Colors.grey.withOpacity(0.55);
    final iconColor =
        enabled ? const Color(0xFF3B82F6) : Colors.grey.withOpacity(0.7);
    final textColor =
        enabled ? Colors.grey.shade400 : Colors.grey.withOpacity(0.7);

    return Material(
      color: Colors.transparent,
      borderRadius: cardRadius,
      child: InkWell(
        borderRadius: cardRadius,
        onTap: enabled ? onTap : null,
        child: Ink(
          height: 96,
          decoration: BoxDecoration(
            borderRadius: cardRadius,
            border: Border.all(
              color: borderColor,
              width: 1.2,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 28,
                  color: iconColor,
                ),
                const SizedBox(height: 10),
                Text(
                  'Добавить место',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w500,
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

class _CoreCandidateCard extends StatelessWidget {
  final PlaceCandidateDto item;
  final bool actionsDisabled;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _CoreCandidateCard({
    required this.item,
    required this.actionsDisabled,
    this.onTap,
    this.onRemove,
  });

  double? _resolveDistanceM() {
    if (item.distanceM != null) return item.distanceM;

    final geo = GeoService.instance.current.value;
    if (geo == null || item.lat == null || item.lng == null) return null;

    return _distanceBetweenMeters(
      geo.lat,
      geo.lng,
      item.lat!,
      item.lng!,
    );
  }

  double _distanceBetweenMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusM = 6371000.0;

    double degToRad(double deg) => deg * math.pi / 180.0;

    final dLat = degToRad(lat2 - lat1);
    final dLng = degToRad(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(degToRad(lat1)) *
            math.cos(degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }

  String? _distanceLabel() {
    final distanceM = _resolveDistanceM();
    if (distanceM == null) return null;

    if (distanceM < 1000) {
      return '${distanceM.round()} м от вас';
    }

    final km = distanceM / 1000;
    final digits = km < 10 ? 2 : 1;
    return '${km.toStringAsFixed(digits)} км от вас';
  }

  Color _distanceColor() {
    final distanceM = _resolveDistanceM();
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

  String? _secondaryLine() {
    if (item.metroName != null && item.metroName!.trim().isNotEmpty) {
      return 'м.${item.metroName}'
          '${item.metroDistanceM != null ? ' · ${item.metroDistanceM} м' : ''}';
    }

    final address = item.address.trim();
    if (address.isNotEmpty) return address;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final distanceLabel = _distanceLabel();
    final secondaryLine = _secondaryLine();
    final cardRadius = BorderRadius.circular(16);

    return Stack(
      children: [
        Material(
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: cardRadius,
            side: const BorderSide(
              color: Colors.white,
              width: 1.2,
            ),
          ),
          child: InkWell(
            borderRadius: cardRadius,
            onTap: actionsDisabled ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final lockedContentWidth = math.max(
                      0.0,
                      constraints.maxWidth - _candidateCardContentLockDelta,
                    );

                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: lockedContentWidth,
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
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  if (distanceLabel != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      distanceLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: _distanceColor(),
                                            fontWeight: FontWeight.w600,
                                            height: 1.0,
                                          ),
                                    ),
                                  ],
                                  if (secondaryLine != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      secondaryLine,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade500,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 6,
            right: _candidateCardContentLockDelta + 6,
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
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _SubmissionCandidateCard({
    required this.item,
    required this.actionsDisabled,
    this.onTap,
    this.onRemove,
  });

  String _moderationLabel() {
    if (item.isRejected) return 'Отклонено';
    if (item.isPendingModeration) return 'На модерации';
    final raw = item.moderationStatus?.trim();
    if (raw == null || raw.isEmpty) return 'На модерации';
    return raw;
  }

  Color _moderationBackgroundColor() {
    if (item.isRejected) {
      return const Color(0x33FF5252);
    }
    return const Color(0x33FFB300);
  }

  Color _moderationTextColor() {
    if (item.isRejected) {
      return const Color(0xFFFF8A80);
    }
    return const Color(0xFFFFB300);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeRightOffset =
        (onRemove != null ? 44.0 : 12.0) + _candidateCardContentLockDelta;
    final reservedRightWidth = onRemove != null ? 144.0 : 110.0;
    final cardRadius = BorderRadius.circular(16);

    return Stack(
      children: [
        Material(
          color: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: cardRadius,
            side: const BorderSide(
              color: Colors.white,
              width: 1.2,
            ),
          ),
          child: InkWell(
            borderRadius: cardRadius,
            onTap: actionsDisabled ? null : onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final lockedContentWidth = math.max(
                      0.0,
                      constraints.maxWidth - _candidateCardContentLockDelta,
                    );

                    return Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: lockedContentWidth,
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
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(
                                      right: reservedRightWidth,
                                    ),
                                    child: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.cityName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: Colors.grey.shade500,
                                      height: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: Colors.grey.shade500,
                                      height: 1.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: badgeRightOffset,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _moderationBackgroundColor(),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _moderationLabel(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: _moderationTextColor(),
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 6,
            right: _candidateCardContentLockDelta + 6,
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
