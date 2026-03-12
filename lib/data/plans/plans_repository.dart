import 'plan_summary_dto.dart';
import 'plan_details_dto.dart';
import 'plan_chat_dto.dart';

abstract class PlansRepository {
  /// Активные планы (archived = false)
  Future<List<PlanSummaryDto>> getMyPlans({
    required String appUserId,
  });

  /// Архив (archived = true)
  Future<List<PlanSummaryDto>> getMyPlansArchive({
    required String appUserId,
  });

  /// Полный snapshot плана
  Future<PlanDetailsDto> getPlanDetails({
    required String appUserId,
    required String planId,
  });

  /// Создание плана
  Future<String> createPlan({
    required String appUserId,
    required String title,
    required String description,
    required DateTime votingDeadlineAt,
    String? initialPlaceId,
  });

  /// Обновить видимость плана (только OWNER)
  Future<void> updatePlanVisibility({
    required String appUserId,
    required String planId,
    required bool visible,
  });

  /// Обновить название плана (только OWNER)
  Future<void> updatePlanTitle({
    required String appUserId,
    required String planId,
    required String title,
  });

  /// Обновить описание плана (только OWNER)
  Future<void> updatePlanDescription({
    required String appUserId,
    required String planId,
    required String description,
  });

  /// Обновить дедлайн голосования (только OWNER, кроме CLOSED)
  Future<void> updatePlanDeadline({
    required String appUserId,
    required String planId,
    required DateTime votingDeadlineAt,
  });

  /// Голосование по месту
  Future<void> votePlanPlace({
    required String appUserId,
    required String planId,
    required String placeId,
  });

  Future<void> votePlanPlaceSubmission({
    required String appUserId,
    required String planId,
    required String placeSubmissionId,
  });

  Future<void> unvotePlanPlace({
    required String appUserId,
    required String planId,
  });

  /// Голосование по дате
  Future<void> votePlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  });

  /// Снять голос по дате
  Future<void> unvotePlanDate({
    required String appUserId,
    required String planId,
  });

  /// Добавить место в план
  Future<void> addPlanPlace({
    required String appUserId,
    required String planId,
    required String placeId,
  });

  /// Удалить место из плана
  Future<void> removePlanPlace({
    required String appUserId,
    required String planId,
    String? placeId,
    String? placeSubmissionId,
  });

  /// Добавить дату в план
  Future<void> addPlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  });

  /// Удалить дату из плана
  Future<void> deletePlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  });

  /// Поставить приоритет даты от создателя
  Future<void> choosePlanDateOwnerPriority({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  });

  /// Снять приоритет даты от создателя
  Future<void> clearPlanDateOwnerPriority({
    required String appUserId,
    required String planId,
  });

  Future<void> choosePlanPlaceOwnerPriority({
    required String appUserId,
    required String planId,
    String? placeId,
    String? placeSubmissionId,
  });

  Future<void> clearPlanPlaceOwnerPriority({
    required String appUserId,
    required String planId,
  });

  /// Выйти из плана
  Future<void> leavePlan({
    required String appUserId,
    required String planId,
  });

  /// Удалить участника (owner)
  Future<void> removeMember({
    required String ownerAppUserId,
    required String planId,
    required String memberAppUserId,
  });

  /// Добавить участника по public_id (owner)
  Future<void> addMemberByPublicId({
    required String appUserId,
    required String planId,
    required String publicId,
  });

  /// Удалить план (owner)
  Future<void> deletePlan({
    required String appUserId,
    required String planId,
  });

  Future<PlanChatSnapshotDto> getPlanChatSnapshot({
    required String appUserId,
    required String planId,
    int limit = 50,
    int? beforeRoomSeq,
  });

  Future<PlanChatSnapshotMessageDto> sendPlanChatMessage({
    required String appUserId,
    required String planId,
    required String text,
    required String clientNonce,
  });

  Future<void> markPlanChatRead({
    required String appUserId,
    required String planId,
    required int readThroughRoomSeq,
  });

  Future<PlanChatBadgesDto> getMyPlanChatBadges({
    required String appUserId,
    bool includeArchived = false,
  });

  /// Создать инвайт (owner)
  Future<String> createInvite({
    required String appUserId,
    required String planId,
  });

  /// Применить инвайт
  Future<String> useInvite({
    required String appUserId,
    required String token,
  });
}
