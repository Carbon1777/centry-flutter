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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final itemWidth = (constraints.maxWidth - gap * 2) / 3;

            Widget buildSlot(int index) {
              if (index < snapshot.candidates.length) {
                final candidate = snapshot.candidates[index];
                return SizedBox(
                  width: itemWidth,
                  child: _DateCandidateCard(
                    candidate: candidate,
                    ownerChoiceModeActive: snapshot.ownerChoiceModeActive,
                    onVote: onVote,
                    onUnvote: onUnvote,
                    onDelete: onDelete,
                    onChooseOwnerPriority: onChooseOwnerPriority,
                    actionsDisabled: actionsDisabled,
                  ),
                );
              }

              return SizedBox(
                width: itemWidth,
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
        ),
        const SizedBox(height: 10),
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: borderWidth),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _CalendarTile(candidate: candidate),
                Positioned(
                  top: 8,
                  left: 10,
                  child: Text(
                    '${candidate.votesCount}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (candidate.canDelete)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: canDeleteTap
                          ? () => onDelete!(candidate.dateTime)
                          : null,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.close,
                          size: 24,
                          color: canDeleteTap
                              ? Colors.red
                              : Colors.red.withOpacity(0.45),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (candidate.isOwnerPriorityChoice) ...[
              const SizedBox(height: 6),
              Text(
                'Выбор создателя',
                style: theme.textTheme.labelMedium,
              ),
            ],
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(6, 28, 6, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            weekday,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dateLabel,
                maxLines: 1,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            timeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
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
          height: 120,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_circle_outline,
                size: 26,
                color: canAddCandidate
                    ? theme.colorScheme.primary
                    : theme.disabledColor,
              ),
              const SizedBox(height: 8),
              Text(
                'Добавить дату',
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
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.disabledColor.withOpacity(0.12),
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
