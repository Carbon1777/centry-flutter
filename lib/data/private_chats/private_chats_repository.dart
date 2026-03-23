import 'private_chat_dto.dart';

abstract class PrivateChatsRepository {
  Future<List<PrivateChatListItemDto>> getPrivateChatsList(
      {required String appUserId});

  Future<PrivateChatBadgesDto> getPrivateChatBadges(
      {required String appUserId});

  Future<PrivateChatSnapshotDto?> getPrivateChatSnapshot({
    required String appUserId,
    required String chatId,
    int limit = 50,
  });

  Future<CreatePrivateChatResultDto> createPrivateChat({
    required String appUserId,
    required String partnerId,
  });

  Future<CanCreatePrivateChatDto> canCreatePrivateChat({
    required String appUserId,
    required String partnerId,
  });

  Future<SentPrivateChatMessageDto> sendMessage({
    required String appUserId,
    required String chatId,
    required String text,
    String? clientNonce,
  });

  Future<void> markChatRead({
    required String appUserId,
    required String chatId,
    required int readThroughSeq,
  });

  Future<bool> deletePrivateChat({
    required String appUserId,
    required String chatId,
  });

  Future<bool> deletePrivateChatAndBlock({
    required String appUserId,
    required String chatId,
  });

  Future<void> editMessage({
    required String appUserId,
    required String chatId,
    required String messageId,
    required String text,
  });

  Future<void> deleteMessageForAll({
    required String appUserId,
    required String chatId,
    required String messageId,
  });

  Future<void> deleteMessageForMe({
    required String appUserId,
    required String chatId,
    required String messageId,
  });

  Future<void> deleteMessagesBulk({
    required String appUserId,
    required String chatId,
    required List<String> messageIds,
    required String mode,
  });
}
