import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';

class PlanPlacesBlock extends StatelessWidget {
  final List<PlaceCandidateDto> items;
  final VoidCallback? onAddCandidate;
  final bool actionsDisabled;

  const PlanPlacesBlock({
    super.key,
    required this.items,
    this.onAddCandidate,
    this.actionsDisabled = false,
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
          Column(
            children: items.map((c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.dividerColor.withOpacity(0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.placeId,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${c.votesCount}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        c.myVote ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
