import 'plan_summary_dto.dart';
import 'plan_details_dto.dart';

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

  /// Голосование по дате
  Future<void> votePlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  });

  /// Добавить место в план
  Future<void> addPlanPlace({
    required String appUserId,
    required String planId,
    required String placeId,
  });

  /// Добавить дату в план
  Future<void> addPlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
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
