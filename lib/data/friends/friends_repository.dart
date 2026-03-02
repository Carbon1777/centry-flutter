import 'friend_dto.dart';
import 'friend_request_result_dto.dart';
import 'accept_friend_result_dto.dart';

abstract class FriendsRepository {
  /// Каноничный список друзей для FriendsScreen.
  /// Server-first: UI обязан рефетчить после любой мутации.
  Future<List<FriendDto>> listMyFriends({
    required String appUserId,
    required String deviceSecret,
  });

  /// Запрос в друзья по Public ID (создаёт PENDING или возвращает существующий).
  Future<FriendRequestResultDto> requestFriendByPublicId({
    required String appUserId,
    required String deviceSecret,
    required String targetPublicId,
  });

  /// Принять входящий запрос.
  Future<AcceptFriendResultDto> acceptFriendRequest({
    required String appUserId,
    required String deviceSecret,
    required String requestId,
  });

  /// Сохранить/очистить заметку (пустая строка => удалить заметку).
  Future<void> upsertFriendNote({
    required String appUserId,
    required String deviceSecret,
    required String friendUserId,
    required String note,
  });

  /// Удалить друга (разрыв дружбы).
  Future<void> removeFriend({
    required String appUserId,
    required String deviceSecret,
    required String friendUserId,
  });
}
