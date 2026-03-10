import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/geo/geo_service.dart';
import '../../../data/plans/plan_details_dto.dart';

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
    final showVotingHint = visibleItems.length < 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showVotingHint) ...[
          Text(
            'Голосование станет доступно, когда появится минимум 2 места.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withOpacity(0.8),
                ),
          ),
          const SizedBox(height: 8),
        ],
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
          height: 112,
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

  static const double _reservedRightWidth = 132.0;
  static const double _deleteTop = 4.0;
  static const double _deleteRight = 0.0;
  static const double _deleteBoxSize = 34.0;

  static const double _buttonWidth = 102.0;
  static const double _buttonRight = 10.0;
  static const double _buttonBottom = 10.0;

  static const double _voteWidth = 38.0;
  static const double _voteHeight = 34.0;
  static const double _voteBottom = 50.0;

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
    final theme = Theme.of(context);
    final distanceLabel = _distanceLabel();
    final secondaryLine = _secondaryLine();
    final cardRadius = BorderRadius.circular(16);
    final opacity = item.isDimmed ? 0.55 : 1.0;
    final canDeleteTap = onRemove != null && !actionsDisabled;
    final voteRight = _buttonRight + (_buttonWidth - _voteWidth) / 2;

    return Opacity(
      opacity: opacity,
      child: Stack(
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
                constraints: const BoxConstraints(minHeight: 112),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = math.max(
                        0.0,
                        constraints.maxWidth - _reservedRightWidth,
                      );

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: contentWidth,
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
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    if (distanceLabel != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        distanceLabel,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
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
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
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
          Positioned(
            top: _deleteTop,
            right: _deleteRight,
            child: SizedBox(
              width: _deleteBoxSize,
              height: _deleteBoxSize,
              child: Align(
                alignment: Alignment.centerRight,
                child: canDeleteTap
                    ? InkWell(
                        onTap: onRemove,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(1),
                          child: Icon(
                            Icons.close,
                            size: 32,
                            color: Colors.redAccent,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          Positioned(
            right: voteRight,
            bottom: _voteBottom,
            child: SizedBox(
              width: _voteWidth,
              height: _voteHeight,
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  '${item.votesCount}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: _buttonRight,
            bottom: _buttonBottom,
            width: _buttonWidth,
            child: _PlaceActionChip(
              label: 'Выбрать',
              enabled: !actionsDisabled,
              onTap: null,
            ),
          ),
        ],
      ),
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

  static const double _reservedRightWidth = 144.0;
  static const double _deleteTop = 4.0;
  static const double _deleteRight = 0.0;
  static const double _deleteBoxSize = 34.0;

  static const double _buttonWidth = 102.0;
  static const double _buttonRight = 10.0;
  static const double _buttonBottom = 10.0;

  static const double _voteWidth = 38.0;
  static const double _voteHeight = 34.0;
  static const double _voteBottom = 50.0;

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
    final cardRadius = BorderRadius.circular(16);
    final opacity = item.isDimmed ? 0.55 : 1.0;
    final canDeleteTap = onRemove != null && !actionsDisabled;
    final voteRight = _buttonRight + (_buttonWidth - _voteWidth) / 2;

    return Opacity(
      opacity: opacity,
      child: Stack(
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
                constraints: const BoxConstraints(minHeight: 112),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = math.max(
                        0.0,
                        constraints.maxWidth - _reservedRightWidth,
                      );

                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: contentWidth,
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
                                      padding: const EdgeInsets.only(right: 8),
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
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        color: Colors.grey.shade500,
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
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
            right: 88,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
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
                  fontSize: 13,
                  height: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: _deleteTop,
            right: _deleteRight,
            child: SizedBox(
              width: _deleteBoxSize,
              height: _deleteBoxSize,
              child: Align(
                alignment: Alignment.centerRight,
                child: canDeleteTap
                    ? InkWell(
                        onTap: onRemove,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(1),
                          child: Icon(
                            Icons.close,
                            size: 32,
                            color: Colors.redAccent,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          Positioned(
            right: voteRight,
            bottom: _voteBottom,
            child: SizedBox(
              width: _voteWidth,
              height: _voteHeight,
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  '${item.votesCount}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: _buttonRight,
            bottom: _buttonBottom,
            width: _buttonWidth,
            child: _PlaceActionChip(
              label: 'Выбрать',
              enabled: !actionsDisabled,
              onTap: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceActionChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final Future<void> Function()? onTap;

  const _PlaceActionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final disabledColor = theme.disabledColor;

    return InkWell(
      onTap: (!enabled || onTap == null) ? null : () => onTap!(),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: enabled
              ? activeColor.withOpacity(0.16)
              : disabledColor.withOpacity(0.12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: enabled ? activeColor : disabledColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
