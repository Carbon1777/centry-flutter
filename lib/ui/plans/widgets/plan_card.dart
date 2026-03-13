import 'package:flutter/material.dart';
import '../../../data/plans/plan_summary_dto.dart';

class PlanCard extends StatelessWidget {
  final PlanSummaryDto plan;
  final VoidCallback onTap;
  final bool showChatUnreadDot;

  const PlanCard({
    super.key,
    required this.plan,
    required this.onTap,
    this.showChatUnreadDot = false,
  });

  String _roleLabel(String role) {
    switch (role) {
      case 'OWNER':
        return 'Роль: Создатель';
      case 'PARTICIPANT':
        return 'Роль: Участник';
      default:
        return role;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return 'Открыт';
      case 'VOTING_FINISHED':
        return 'Голосование окончено';
      case 'CLOSED':
        return 'Закрыт';
      default:
        return status;
    }
  }

  Color _roleColor() {
    if (plan.role == 'OWNER') {
      return const Color(0xFF3B82F6);
    } else {
      return const Color(0xFF14B8A6);
    }
  }

  Color _statusColor() {
    switch (plan.status) {
      case 'OPEN':
        return const Color(0xFF22C55E);
      case 'VOTING_FINISHED':
        return const Color(0xFFFACC15);
      case 'CLOSED':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey.shade400;
    }
  }

  Color _deadlineColor() {
    if (plan.votingDeadlineAt == null) {
      return Colors.grey.shade400;
    }

    final now = DateTime.now();
    final diff = plan.votingDeadlineAt!.difference(now);
    final hours = diff.inHours;

    if (hours >= 120) {
      return const Color(0xFF22C55E);
    } else if (hours >= 72) {
      return const Color(0xFFFACC15);
    } else if (hours >= 24) {
      return const Color(0xFFFB923C);
    } else {
      return const Color(0xFFEF4444);
    }
  }

  String _formatDeadline(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final roleText = _roleLabel(plan.role);
    final statusText = _statusLabel(plan.status);

    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          height: 1.1,
        );

    final headerColor = titleStyle?.color ?? Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    plan.title,
                    style: titleStyle,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        roleText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _roleColor(),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Text(
                        'Участники: ${plan.membersCount}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  if (plan.status == 'OPEN' && plan.votingDeadlineAt != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Дедлайн голосования: ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: headerColor,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatDeadline(plan.votingDeadlineAt!),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _deadlineColor(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              if (showChatUnreadDot)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 10,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
