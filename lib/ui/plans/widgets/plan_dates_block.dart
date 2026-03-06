import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import 'plan_formatters.dart';

class PlanDatesBlock extends StatelessWidget {
  /// Legacy contract: оставляем, чтобы не сломать текущий экран,
  /// пока `plan_details_screen.dart` ещё не переведён на `dateVoting`.
  final List<DateCandidateDto> items;

  /// Новый server-first snapshot блока дат.
  final PlanDateVotingDto? dateVoting;

  /// Callbacks для нового server-first режима.
  final Future<void> Function(DateTime dateAt)? onVote;
  final Future<void> Function(DateTime dateAt)? onUnvote;
  final Future<void> Function(DateTime dateAt)? onDelete;
  final Future<void> Function(DateTime dateAt)? onChooseOwnerPriority;
  final Future<void> Function()? onAddCandidate;

  /// Внешний флаг загрузки, чтобы гасить повторные нажатия.
  final bool actionsDisabled;

  const PlanDatesBlock({
    super.key,
    this.items = const [],
    this.dateVoting,
    this.onVote,
    this.onUnvote,
    this.onDelete,
    this.onChooseOwnerPriority,
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
  final Future<void> Function()? onAddCandidate;
  final bool actionsDisabled;

  const _ServerFirstPlanDatesBlock({
    required this.snapshot,
    required this.onVote,
    required this.onUnvote,
    required this.onDelete,
    required this.onChooseOwnerPriority,
    required this.onAddCandidate,
    required this.actionsDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cards = List<Widget>.generate(3, (index) {
      if (index < snapshot.candidates.length) {
        final candidate = snapshot.candidates[index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 2 ? 8 : 0),
            child: _DateCandidateCard(
              candidate: candidate,
              ownerChoiceModeActive: snapshot.ownerChoiceModeActive,
              onVote: onVote,
              onUnvote: onUnvote,
              onDelete: onDelete,
              onChooseOwnerPriority: onChooseOwnerPriority,
              actionsDisabled: actionsDisabled,
            ),
          ),
        );
      }

      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: index < 2 ? 8 : 0),
          child: _EmptyDateSlot(
            canAddCandidate: snapshot.canAddCandidate,
            onTap: (!actionsDisabled && snapshot.canAddCandidate)
                ? onAddCandidate
                : null,
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: cards,
        ),
        const SizedBox(height: 12),
        if (snapshot.postDeadlineGraceActive)
          Text(
            'Голосование завершено. Победитель пока не определен.',
            style: theme.textTheme.bodySmall,
          )
        else if (snapshot.ownerChoiceModeActive)
          Text(
            'Доступен приоритетный выбор создателя.',
            style: theme.textTheme.bodySmall,
          )
        else if (snapshot.isVotingActive)
          Text(
            'До конца голосования: ${snapshot.hoursLeftToDeadline} ч.',
            style: theme.textTheme.bodySmall,
          )
        else if (snapshot.candidatesCount < 2)
          Text(
            'Голосование станет доступно, когда появится минимум 2 даты.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _DateCandidateCard extends StatelessWidget {
  final PlanDateVotingCandidateDto candidate;
  final bool ownerChoiceModeActive;
  final Future<void> Function(DateTime dateAt)? onVote;
  final Future<void> Function(DateTime dateAt)? onUnvote;
  final Future<void> Function(DateTime dateAt)? onDelete;
  final Future<void> Function(DateTime dateAt)? onChooseOwnerPriority;
  final bool actionsDisabled;

  const _DateCandidateCard({
    required this.candidate,
    required this.ownerChoiceModeActive,
    required this.onVote,
    required this.onUnvote,
    required this.onDelete,
    required this.onChooseOwnerPriority,
    required this.actionsDisabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color borderColor = theme.dividerColor;
    double borderWidth = 1;

    if (candidate.isWinner) {
      borderColor = Colors.green;
      borderWidth = 2;
    } else if (candidate.isAvailableForOwnerChoiceNow) {
      borderColor = Colors.red;
      borderWidth = 2;
    } else if (candidate.isUserVotedForThis) {
      borderColor = theme.colorScheme.primary;
      borderWidth = 2;
    }

    final opacity = candidate.isDimmed ? 0.55 : 1.0;
    final canDeleteTap =
        candidate.canDelete && !actionsDisabled && onDelete != null;
    final actionTap = !actionsDisabled ? _resolvePrimaryAction() : null;
    final actionEnabled = actionTap != null;

    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CalendarTile(candidate: candidate),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.how_to_vote_outlined, size: 16),
                const SizedBox(width: 6),
                Text(
                  '${candidate.votesCount}',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                if (candidate.isLeading && !candidate.isWinner)
                  Text(
                    'Лидер',
                    style: theme.textTheme.labelSmall,
                  ),
                if (candidate.canDelete) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: canDeleteTap
                        ? () => onDelete!(candidate.dateTime)
                        : null,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: canDeleteTap
                            ? Colors.red
                            : Colors.red.withOpacity(0.45),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (candidate.isOwnerPriorityChoice) ...[
              const SizedBox(height: 8),
              Text(
                'Выбор создателя',
                style: theme.textTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 10),
            _ActionChip(
              label: _buildActionLabel(),
              enabled: actionEnabled,
              onTap: actionTap,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> Function()? _resolvePrimaryAction() {
    if (candidate.isWinner) return null;
    if (candidate.canUnvote && onUnvote != null) {
      return () => onUnvote!(candidate.dateTime);
    }
    if (candidate.canVote && onVote != null) {
      return () => onVote!(candidate.dateTime);
    }
    if (candidate.isAvailableForOwnerChoiceNow &&
        onChooseOwnerPriority != null) {
      return () => onChooseOwnerPriority!(candidate.dateTime);
    }
    return null;
  }

  String _buildActionLabel() {
    if (candidate.isWinner) return 'Победитель';
    if (candidate.canUnvote) return 'Снять';
    if (candidate.canVote) return 'Выбрать';
    if (candidate.isAvailableForOwnerChoiceNow) return 'Выбрать';
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

    final weekday = candidate.weekdayRu.isNotEmpty
        ? candidate.weekdayRu
        : _weekdayRu(candidate.dateTime);
    final dateLabel = candidate.dateLabel.isNotEmpty
        ? candidate.dateLabel
        : _fallbackDateLabel(candidate.dateTime);
    final timeLabel = candidate.timeLabel.isNotEmpty
        ? candidate.timeLabel
        : _fallbackTimeLabel(candidate.dateTime);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            dateLabel,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            timeLabel,
            style: theme.textTheme.bodyMedium,
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
          height: 170,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 28,
                color: canAddCandidate
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              const SizedBox(height: 10),
              Text(
                'Добавить дату мероприятия для голосования',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
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

  const _ActionChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: (!enabled || onTap == null) ? null : () => onTap!(),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: enabled
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.disabledColor.withValues(alpha: 0.12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge?.copyWith(
            color: enabled ? theme.colorScheme.primary : theme.disabledColor,
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
      return 'Понедельник';
    case DateTime.tuesday:
      return 'Вторник';
    case DateTime.wednesday:
      return 'Среда';
    case DateTime.thursday:
      return 'Четверг';
    case DateTime.friday:
      return 'Пятница';
    case DateTime.saturday:
      return 'Суббота';
    case DateTime.sunday:
      return 'Воскресенье';
  }
  return '';
}
