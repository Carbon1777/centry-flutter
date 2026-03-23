import 'attention_sign_dto.dart';

abstract class AttentionSignsRepository {
  Future<AttentionSignBoxDto> getMyBox({required String appUserId});

  Future<SendAttentionSignResultDto> sendSign({
    required String appUserId,
    required String targetUserId,
    required String dailySignId,
  });

  Future<bool> acceptSign({
    required String appUserId,
    required String submissionId,
  });

  Future<bool> declineSign({
    required String appUserId,
    required String submissionId,
  });

  Future<String?> useFriendInviteRight({
    required String appUserId,
    required String submissionId,
  });

  /// Атомарно: помечает право использованным + отправляет запрос в друзья.
  /// Возвращает true если операция прошла успешно (включая ALREADY_FRIENDS/PENDING).
  Future<bool> useFriendInviteRightAndRequest({
    required String appUserId,
    required String submissionId,
  });
}
