import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import '../../../data/plans/plans_repository.dart';
import 'plan_chat_sheet.dart';

class PlanChatBlock extends StatelessWidget {
  final List<PlanChatMessageDto> items;
  final String currentUserId;
  final String planId;
  final PlansRepository repository;
  final Map<String, String> nicknamesByUserId;
  final double availableHeight;

  const PlanChatBlock({
    super.key,
    required this.items,
    required this.currentUserId,
    required this.planId,
    required this.repository,
    required this.nicknamesByUserId,
    required this.availableHeight,
  });

  @override
  Widget build(BuildContext context) {
    return PlanChatSheet(
      items: items,
      currentUserId: currentUserId,
      nicknamesByUserId: nicknamesByUserId,
      availableHeight: availableHeight,
    );
  }
}
