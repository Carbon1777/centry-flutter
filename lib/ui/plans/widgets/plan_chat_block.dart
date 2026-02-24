import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import 'plan_formatters.dart';

class PlanChatBlock extends StatelessWidget {
  final List<PlanChatMessageDto> items;

  const PlanChatBlock({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Чат пуст');
    }

    return Column(
      children: items.map((m) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.authorAppUserId,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(m.text),
              const SizedBox(height: 4),
              Text(
                formatPlanDateTime(m.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
