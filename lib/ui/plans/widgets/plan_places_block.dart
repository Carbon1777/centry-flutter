import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/geo/geo_service.dart';
import '../../../data/plans/plan_details_dto.dart';

const int _candidateSlotsCount = 5;

class PlanPlacesBlock extends StatelessWidget {
  final List<PlaceCandidateDto> items;
  final PlanPlaceVotingDto? placeVoting;
  final Future<void> Function()? onAddCandidate;
  final bool actionsDisabled;
  final ValueChanged<PlaceCandidateDto>? onOpenDetails;
  final ValueChanged<PlaceCandidateDto>? onRemoveCandidate;
  final Future<void> Function(PlaceCandidateDto candidate)? onVote;
  final Future<void> Function(PlaceCandidateDto candidate)? onUnvote;
  final Future<void> Function(PlaceCandidateDto candidate)?
      onChooseOwnerPriority;
  final Future<void> Function()? onClearOwnerPriority;

  const PlanPlacesBlock({
    super.key,
    required this.items,
    this.placeVoting,
    this.onAddCandidate,
    this.actionsDisabled = false,
    this.onOpenDetails,
    this.onRemoveCandidate,
    this.onVote,
    this.onUnvote,
    this.onChooseOwnerPriority,
    this.onClearOwnerPriority,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = placeVoting;
    if (snapshot != null) {
      return _ServerFirstPlanPlacesBlock(
        snapshot: snapshot,
        onAddCandidate: onAddCandidate,
        actionsDisabled: actionsDisabled,
        onOpenDetails: onOpenDetails,
        onRemoveCandidate: onRemoveCandidate,
        onVote: onVote,
        onUnvote: onUnvote,
        onChooseOwnerPriority: onChooseOwnerPriority,
        onClearOwnerPriority: onClearOwnerPriority,
      );
    }

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
                      ?.withValues(alpha: 0.8),
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
              return _PlaceCandidateCard(
                item: item,
                actionsDisabled: actionsDisabled,
                onTap:
                    onOpenDetails == null ? null : () => onOpenDetails!(item),
                onRemove: item.canDelete &&
                        onRemoveCandidate != null &&
                        !actionsDisabled
                    ? () => onRemoveCandidate!(item)
                    : null,
                onActionTap: null,
                actionLabel: 'Недоступно',
                actionEnabled: false,
                ownerChoiceModeActive: false,
                hasOwnerPriorityChoice: false,
                isFinalizedWithWinner: false,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ServerFirstPlanPlacesBlock extends StatelessWidget {
  final PlanPlaceVotingDto snapshot;
  final Future<void> Function()? onAddCandidate;
  final bool actionsDisabled;
  final ValueChanged<PlaceCandidateDto>? onOpenDetails;
  final ValueChanged<PlaceCandidateDto>? onRemoveCandidate;
  final Future<void> Function(PlaceCandidateDto candidate)? onVote;
  final Future<void> Function(PlaceCandidateDto candidate)? onUnvote;
  final Future<void> Function(PlaceCandidateDto candidate)?
      onChooseOwnerPriority;
  final Future<void> Function()? onClearOwnerPriority;

  const _ServerFirstPlanPlacesBlock({
    required this.snapshot,
    required this.onAddCandidate,
    required this.actionsDisabled,
    required this.onOpenDetails,
    required this.onRemoveCandidate,
    required this.onVote,
    required this.onUnvote,
    required this.onChooseOwnerPriority,
    required this.onClearOwnerPriority,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFinalizedWithWinner = snapshot.finalWinnerCandidateId != null;
    final hasOwnerPriorityChoice = snapshot.candidates.any(
      (c) => c.isOwnerPriorityChoice,
    );

    TextStyle? helperStyle = theme.textTheme.bodySmall;
    String? helperText;

    if (snapshot.postDeadlineGraceActive) {
      helperText = 'Голосование завершено. Победитель пока не определен.';
    } else if (hasOwnerPriorityChoice && !isFinalizedWithWinner) {
      helperText = 'Создатель поставил свой приоритет по месту.';
      helperStyle = theme.textTheme.bodySmall?.copyWith(
        color: Colors.amber,
        fontWeight: FontWeight.w700,
      );
    } else if (snapshot.ownerChoiceModeActive) {
      helperText = 'Доступен приоритетный выбор создателя.';
    } else if (snapshot.candidatesCount < 2) {
      helperText =
          'Голосование станет доступно, когда появится минимум 2 места.';
    }

    final visibleItems =
        snapshot.candidates.take(_candidateSlotsCount).toList();
    final canAdd =
        snapshot.canAddCandidate && !actionsDisabled && onAddCandidate != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (helperText != null) ...[
          Text(helperText, style: helperStyle),
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
              final actionTap =
                  !actionsDisabled ? _resolvePrimaryAction(item) : null;
              final actionLabel = _buildActionLabel(item);

              return _PlaceCandidateCard(
                item: item,
                actionsDisabled: actionsDisabled,
                onTap:
                    onOpenDetails == null ? null : () => onOpenDetails!(item),
                onRemove: item.canDelete &&
                        onRemoveCandidate != null &&
                        !actionsDisabled
                    ? () => onRemoveCandidate!(item)
                    : null,
                onActionTap: actionTap,
                actionLabel: actionLabel,
                actionEnabled: actionTap != null,
                ownerChoiceModeActive: snapshot.ownerChoiceModeActive,
                hasOwnerPriorityChoice: hasOwnerPriorityChoice,
                isFinalizedWithWinner: isFinalizedWithWinner,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> Function()? _resolvePrimaryAction(PlaceCandidateDto candidate) {
    if (candidate.isWinner) return null;

    if (candidate.canClearOwnerPriority && onClearOwnerPriority != null) {
      return () => onClearOwnerPriority!();
    }

    if (candidate.isAvailableForOwnerChoiceNow &&
        onChooseOwnerPriority != null) {
      return () => onChooseOwnerPriority!(candidate);
    }

    if (candidate.canUnvote && onUnvote != null) {
      return () => onUnvote!(candidate);
    }

    if (candidate.canVote && onVote != null) {
      return () => onVote!(candidate);
    }

    return null;
  }

  String _buildActionLabel(PlaceCandidateDto candidate) {
    if (candidate.canClearOwnerPriority) return 'Снять';
    if (candidate.isAvailableForOwnerChoiceNow) return 'Приоритет';
    if (candidate.canUnvote) return 'Снять';
    if (candidate.canVote) return 'Выбрать';
    return 'Недоступно';
  }
}

class _AddCandidateSlot extends StatelessWidget {
  final bool enabled;
  final Future<void> Function()? onTap;

  const _AddCandidateSlot({
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = BorderRadius.circular(16);
    final borderColor = Colors.grey.withValues(alpha: 0.55);
    final iconColor =
        enabled ? const Color(0xFF3B82F6) : Colors.grey.withValues(alpha: 0.7);
    final textColor =
        enabled ? Colors.grey.shade400 : Colors.grey.withValues(alpha: 0.7);

    return Material(
      color: Colors.transparent,
      borderRadius: cardRadius,
      child: InkWell(
        borderRadius: cardRadius,
        onTap: enabled && onTap != null ? () => onTap!() : null,
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

class _PlaceCandidateCard extends StatelessWidget {
  final PlaceCandidateDto item;
  final bool actionsDisabled;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final Future<void> Function()? onActionTap;
  final String actionLabel;
  final bool actionEnabled;
  final bool ownerChoiceModeActive;
  final bool hasOwnerPriorityChoice;
  final bool isFinalizedWithWinner;

  const _PlaceCandidateCard({
    required this.item,
    required this.actionsDisabled,
    required this.onTap,
    required this.onRemove,
    required this.onActionTap,
    required this.actionLabel,
    required this.actionEnabled,
    required this.ownerChoiceModeActive,
    required this.hasOwnerPriorityChoice,
    required this.isFinalizedWithWinner,
  });

  static const double _reservedRightWidth = 80.0;
  static const double _deleteTop = 4.0;
  static const double _deleteRight = 4.0;
  static const double _deleteBoxSize = 34.0;

  static const double _buttonWidth = 102.0;
  static const double _buttonRight = 10.0;
  static const double _buttonBottom = 10.0;

  static const double _voteWidth = 38.0;
  static const double _voteHeight = 34.0;
  static const double _voteBottom = 50.0;

  bool get _showModerationBadge => item.isSubmissionPlace;

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

  String? _coreSecondaryLine() {
    if (item.metroName != null && item.metroName!.trim().isNotEmpty) {
      return 'м.${item.metroName}'
          '${item.metroDistanceM != null ? ' · ${item.metroDistanceM} м' : ''}';
    }
    return null;
  }

  String? _submissionSecondaryLine() {
    final address = item.address.trim();
    if (address.isNotEmpty) return address;
    return null;
  }

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

  Widget _buildModerationBadge(ThemeData theme) {
    return Transform.translate(
      offset: const Offset(0, -8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            color: _moderationTextColor(),
            fontWeight: FontWeight.w700,
            fontSize: 13,
            height: 1,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardRadius = BorderRadius.circular(16);
    final isOwnerPriorityCandidate = !isFinalizedWithWinner &&
        ownerChoiceModeActive &&
        item.isAvailableForOwnerChoiceNow;
    final opacity =
        isOwnerPriorityCandidate ? 1.0 : (item.isDimmed ? 0.55 : 1.0);
    final canDeleteTap = onRemove != null && !actionsDisabled;
    const voteRight = _buttonRight + (_buttonWidth - _voteWidth) / 2;
    final distanceLabel = _distanceLabel();
    final coreSecondaryLine = _coreSecondaryLine();
    final submissionSecondaryLine = _submissionSecondaryLine();

    final isPriorityAction =
        item.canClearOwnerPriority || item.isAvailableForOwnerChoiceNow;

    Color borderColor = Colors.white;
    double borderWidth = 1.2;

    if (item.isWinner) {
      borderColor = Colors.green;
      borderWidth = 2;
    } else if (item.isAvailableForOwnerChoiceNow) {
      borderColor = Colors.amber;
      borderWidth = 2;
    } else if (!isFinalizedWithWinner &&
        !ownerChoiceModeActive &&
        !hasOwnerPriorityChoice &&
        item.isUserVotedForThis) {
      borderColor = theme.colorScheme.primary;
      borderWidth = 2;
    }

    return Opacity(
      opacity: opacity,
      child: Stack(
        children: [
          Material(
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: cardRadius,
              side: BorderSide(
                color: borderColor,
                width: borderWidth,
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
                                  child: _buildPreview(),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: Text(
                                              item.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  theme.textTheme.titleMedium,
                                            ),
                                          ),
                                        ),
                                        if (_showModerationBadge)
                                          _buildModerationBadge(theme),
                                      ],
                                    ),
                                    if (!_showModerationBadge) ...[
                                      if (distanceLabel != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          distanceLabel,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: _distanceColor(),
                                            fontWeight: FontWeight.w600,
                                            height: 1.0,
                                          ),
                                        ),
                                      ],
                                      if (coreSecondaryLine != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          coreSecondaryLine,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ],
                                    if (_showModerationBadge &&
                                        item.cityName.trim().isNotEmpty) ...[
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
                                    ],
                                    if (_showModerationBadge &&
                                        submissionSecondaryLine != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        submissionSecondaryLine,
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
                child: item.isWinner
                    ? const Icon(
                        Icons.emoji_events_outlined,
                        size: 28,
                        color: Colors.amber,
                      )
                    : item.isOwnerPriorityChoice
                        ? const Icon(
                            Icons.flag_rounded,
                            size: 26,
                            color: Colors.amber,
                          )
                        : canDeleteTap
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
              label: actionLabel,
              enabled: actionEnabled,
              onTap: onActionTap,
              isPriority: isPriorityAction,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (item.isCorePlace) {
      final url = item.previewMediaUrl;
      if (url != null && url.isNotEmpty) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/images/place_placeholder.png',
            fit: BoxFit.cover,
          ),
        );
      }

      final key = item.previewStorageKey;
      if (key != null && key.isNotEmpty) {
        final publicUrl = Supabase.instance.client.storage
            .from('brand-media')
            .getPublicUrl(key);
        return Image.network(
          publicUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            'assets/images/place_placeholder.png',
            fit: BoxFit.cover,
          ),
        );
      }
    }

    return Image.asset(
      'assets/images/place_placeholder.png',
      fit: BoxFit.cover,
    );
  }
}

class _PlaceActionChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final Future<void> Function()? onTap;
  final bool isPriority;

  const _PlaceActionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.isPriority = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = isPriority ? Colors.amber : theme.colorScheme.primary;
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
              ? activeColor.withValues(alpha: 0.16)
              : disabledColor.withValues(alpha: 0.12),
          border: enabled && isPriority
              ? Border.all(color: Colors.amber.withValues(alpha: 0.65))
              : null,
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
