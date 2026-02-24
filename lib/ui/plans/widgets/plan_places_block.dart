import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';

class PlanPlacesBlock extends StatelessWidget {
  final List<PlaceCandidateDto> items;

  const PlanPlacesBlock({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Нет мест');
    }

    return Column(
      children: items.map((c) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: Text(c.placeId)),
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
