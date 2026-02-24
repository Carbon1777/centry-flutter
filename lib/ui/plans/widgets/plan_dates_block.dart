import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import 'plan_formatters.dart';

class PlanDatesBlock extends StatelessWidget {
  final List<DateCandidateDto> items;

  const PlanDatesBlock({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
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
