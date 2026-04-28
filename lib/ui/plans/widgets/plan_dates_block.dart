import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import 'plan_formatters.dart';

class PlanDatesBlock extends StatelessWidget {
  final List<DateCandidateDto> items;
  final PlanDateVotingDto? dateVoting;

  final Future<void> Function(DateTime dateAt)? onVote;
  final Future<void> Function(DateTime dateAt)? onUnvote;
  final Future<void> Function(DateTime dateAt)? onDelete;
  final Future<void> Function(DateTime dateAt)? onChooseOwnerPriority;
  final Future<void> Function()? onClearOwnerPriority;
  final Future<void> Function()? onAddCandidate;

  final bool actionsDisabled;

  const PlanDatesBlock({
    super.key,
    this.items = const [],
    this.dateVoting,
    this.onVote,
    this.onUnvote,
    this.onDelete,
    this.onChooseOwnerPriority,
    this.onClearOwnerPriority,
    this.onAddCandidate,
    this.actionsDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = dateVoting;
    if (snapshot != null) {
      return _ServerFirstPlanDatesBlock(
        snapshot: snapshot,
        onVote: onVote,
        onUnvote: onUnvote,
        onDelete: onDelete,
        onChooseOwnerPriority: onChooseOwnerPriority,
        onClearOwnerPriority: onClearOwnerPriority,
        onAddCandidate: onAddCandidate,
        actionsDisabled: actionsDisabled,
      );
    }

    if (items.isEmpty) {
      return const Text('Нет дат');
    }

    return Column(
      children: items.map((c) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(formatPlanDateTime(c.dateAt))),
              Text('${c.votesCount}'),
              const SizedBox(width: 10),
              Icon(
                c.myVote ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ServerFirstPlanDatesBlock extends StatelessWidget {
  final PlanDateVotingDto snapshot;
  final Future<void> Function(DateTime dateAt)? onVote;
  final Future<void> Function(DateTime dateAt)? onUnvote;
  final Future<void> Function(DateTime dateAt)? onDelete;
  final Future<void> Function(DateTime dateAt)? onChooseOwnerPriority;
  final Future<void> Function()? onClearOwnerPriority;
  final Future<void> Function()? onAddCandidate;
  final bool actionsDisabled;

  const _ServerFirstPlanDatesBlock({
    required this.snapshot,
    required this.onVote,
    required this.onUnvote,
    required this.onDelete,
    required this.onChooseOwnerPriority,
    required this.onClearOwnerPriority,
    required this.onAddCandidate,
    required this.actionsDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final isFinalizedWithWinner = snapshot.finalWinnerCandidateId != null;
    final hasOwnerPriorityChoice = snapshot.candidates.any(
      (c) => c.isOwnerPriorityChoice,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final itemWidth = (constraints.maxWidth - gap * 2) / 3;
        // Адаптивная высота: на узком iPhone (itemWidth ~115) карточка
        // приближается к квадрату (~92px), на широком iPad (itemWidth ~260)
        // ограничивается сверху, чтобы не съедать пространство блока мест.
        final slotHeight =
            (itemWidth * 0.8).clamp(80.0, 110.0).toDouble();

        Widget buildSlot(int index) {
          if (index < snapshot.candidates.length) {
            final candidate = snapshot.candidates[index];
            return SizedBox(
              width: itemWidth,
              child: _DateCandidateCard(
                candidate: candidate,
                ownerChoiceModeActive: snapshot.ownerChoiceModeActive,
                hasOwnerPriorityChoice: hasOwnerPriorityChoice,
                isFinalizedWithWinner: isFinalizedWithWinner,
                onVote: onVote,
                onUnvote: onUnvote,
                onDelete: onDelete,
                onChooseOwnerPriority: onChooseOwnerPriority,
                onClearOwnerPriority: onClearOwnerPriority,
                actionsDisabled: actionsDisabled,
              ),
            );
          }

          return SizedBox(
            width: itemWidth,
            height: slotHeight,
            child: _EmptyDateSlot(
              canAddCandidate: snapshot.canAddCandidate,
              onTap: (!actionsDisabled && snapshot.canAddCandidate)
                  ? onAddCandidate
                  : null,
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSlot(0),
            const SizedBox(width: gap),
            buildSlot(1),
            const SizedBox(width: gap),
            buildSlot(2),
          ],
        );
      },
    );
  }
}

class _DateCandidateCard extends StatelessWidget {
  final PlanDateVotingCandidateDto candidate;
  final bool ownerChoiceModeActive;
  final bool hasOwnerPriorityChoice;
  final bool isFinalizedWithWinner;
  final Future<void> Function(DateTime dateAt)? onVote;
  final Future<void> Function(DateTime dateAt)? onUnvote;
  final Future<void> Function(DateTime dateAt)? onDelete;
  final Future<void> Function(DateTime dateAt)? onChooseOwnerPriority;
  final Future<void> Function()? onClearOwnerPriority;
  final bool actionsDisabled;

  const _DateCandidateCard({
    required this.candidate,
    required this.ownerChoiceModeActive,
    required this.hasOwnerPriorityChoice,
    required this.isFinalizedWithWinner,
    required this.onVote,
    required this.onUnvote,
    required this.onDelete,
    required this.onChooseOwnerPriority,
    required this.onClearOwnerPriority,
    required this.actionsDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwnerPriorityCandidate = !isFinalizedWithWinner &&
        ownerChoiceModeActive &&
        candidate.isAvailableForOwnerChoiceNow;

    Color borderColor = theme.dividerColor;
    double borderWidth = 1;

    if (candidate.isWinner) {
      borderColor = Colors.green;
      borderWidth = 2;
    } else if (isOwnerPriorityCandidate) {
      borderColor = Colors.amber;
      borderWidth = 2;
    } else if (!isFinalizedWithWinner &&
        !ownerChoiceModeActive &&
        !hasOwnerPriorityChoice &&
        candidate.isUserVotedForThis) {
      borderColor = theme.colorScheme.primary;
      borderWidth = 2;
    }

    final opacity =
        isOwnerPriorityCandidate ? 1.0 : (candidate.isDimmed ? 0.55 : 1.0);

    final canDeleteTap =
        candidate.canDelete && !actionsDisabled && onDelete != null;
    final actionTap = !actionsDisabled ? _resolvePrimaryAction() : null;
    final actionEnabled = actionTap != null;
    final shouldShowActionChip = actionEnabled;
    final isPriorityAction = candidate.canClearOwnerPriority ||
        candidate.isAvailableForOwnerChoiceNow;

    const overlayLeftInset = 6.0;
    const overlayRightInset = 0.0;
    const overlayTop = 2.0;
    const overlayBoxSize = 34.0;

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _CalendarTile(candidate: candidate),
                Positioned(
                  top: overlayTop,
                  left: overlayLeftInset,
                  child: SizedBox(
                    width: overlayBoxSize,
                    height: overlayBoxSize,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${candidate.votesCount}',
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
                  top: overlayTop,
                  right: overlayRightInset,
                  child: SizedBox(
                    width: overlayBoxSize,
                    height: overlayBoxSize,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: candidate.isWinner
                          ? const Icon(
                              Icons.emoji_events_outlined,
                              size: 28,
                              color: Colors.amber,
                            )
                          : candidate.isOwnerPriorityChoice
                              ? const Icon(
                                  Icons.flag_rounded,
                                  size: 26,
                                  color: Colors.amber,
                                )
                              : candidate.canDelete
                                  ? InkWell(
                                      onTap: canDeleteTap
                                          ? () => onDelete!(candidate.dateTime)
                                          : null,
                                      borderRadius: BorderRadius.circular(999),
                                      child: Padding(
                                        padding: const EdgeInsets.all(1),
                                        child: Icon(
                                          Icons.close,
                                          size: 32,
                                          color: canDeleteTap
                                              ? Colors.redAccent
                                              : Colors.redAccent
                                                  .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    )
                                  : null,
                    ),
                  ),
                ),
              ],
            ),
            if (shouldShowActionChip) ...[
              const SizedBox(height: 8),
              _ActionChip(
                label: _buildActionLabel(),
                enabled: actionEnabled,
                onTap: actionTap,
                isPriority: isPriorityAction,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> Function()? _resolvePrimaryAction() {
    if (candidate.isWinner) return null;

    if (candidate.canClearOwnerPriority && onClearOwnerPriority != null) {
      return () => onClearOwnerPriority!();
    }

    if (candidate.isAvailableForOwnerChoiceNow &&
        onChooseOwnerPriority != null) {
      return () => onChooseOwnerPriority!(candidate.dateTime);
    }

    if (candidate.canUnvote && onUnvote != null) {
      return () => onUnvote!(candidate.dateTime);
    }

    if (candidate.canVote && onVote != null) {
      return () => onVote!(candidate.dateTime);
    }

    return null;
  }

  String _buildActionLabel() {
    if (candidate.canClearOwnerPriority) return 'Снять';
    if (candidate.isAvailableForOwnerChoiceNow) return 'Приоритет';
    if (candidate.canUnvote) return 'Снять';
    if (candidate.canVote) return 'Выбрать';
    if (ownerChoiceModeActive && !candidate.isAvailableForOwnerChoiceNow) {
      return 'Недоступно';
    }
    return 'Недоступно';
  }
}

class _CalendarTile extends StatelessWidget {
  final PlanDateVotingCandidateDto candidate;

  const _CalendarTile({
    required this.candidate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final local = candidate.dateTime.toLocal();
    final weekday = _weekdayRu(local);
    final dateLabel = _fallbackDateLabel(local);
    final timeLabel = _fallbackTimeLabel(local);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            weekday,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dateLabel,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyDateSlot extends StatelessWidget {
  final bool canAddCandidate;
  final Future<void> Function()? onTap;

  const _EmptyDateSlot({
    required this.canAddCandidate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap == null ? null : () => onTap!(),
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: canAddCandidate ? 1 : 0.6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 22,
                color: canAddCandidate
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  'Добавить дату',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final bool enabled;
  final Future<void> Function()? onTap;
  final bool isPriority;

  const _ActionChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: enabled
              ? activeColor.withValues(alpha: 0.16)
              : disabledColor.withValues(alpha: 0.12),
          border: enabled && isPriority
              ? Border.all(color: Colors.amber.withValues(alpha: 0.65))
              : null,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              color: enabled ? activeColor : disabledColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

String _fallbackDateLabel(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  return '$day/$month/$year';
}

String _fallbackTimeLabel(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _weekdayRu(DateTime value) {
  switch (value.weekday) {
    case DateTime.monday:
      return 'Пн';
    case DateTime.tuesday:
      return 'Вт';
    case DateTime.wednesday:
      return 'Ср';
    case DateTime.thursday:
      return 'Чт';
    case DateTime.friday:
      return 'Пт';
    case DateTime.saturday:
      return 'Сб';
    case DateTime.sunday:
      return 'Вс';
  }
  return '';
}
