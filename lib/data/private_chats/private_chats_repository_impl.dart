import 'package:supabase_flutter/supabase_flutter.dart';

import 'private_chat_dto.dart';
import 'private_chats_repository.dart';

class PrivateChatsRepositoryImpl implements PrivateChatsRepository {
  final SupabaseClient _client;

  PrivateChatsRepositoryImpl(this._client);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Expected map response, got: $value');
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    throw Exception('Expected list response, got: $value');
  }

  @override
  Future<List<PrivateChatListItemDto>> getPrivateChatsList(
      {required String appUserId}) async {
    final response = await _client.rpc(
      'get_private_chats_list_v1',
      params: {'p_user_id': appUserId},
    );
    return _asList(response)
        .map((e) =>
            PrivateChatListItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<PrivateChatBadgesDto> getPrivateChatBadges(
      {required String appUserId}) async {
    final response = await _client.rpc(
      'get_private_chat_badges_v1',
      params: {'p_user_id': appUserId},
    );
    return PrivateChatBadgesDto.fromJson(_asMap(response));
  }

  @override
  Future<PrivateChatSnapshotDto?> getPrivateChatSnapshot({
    required String appUserId,
    required String chatId,
    int limit = 50,
  }) async {
    final response = await _client.rpc(
      'get_private_chat_snapshot_v1',
      params: {
        'p_user_id': appUserId,
        'p_chat_id': chatId,
        'p_limit': limit,
      },
    );
    final map = _asMap(response);
    if (map['error'] != null) return null;
    return PrivateChatSnapshotDto.fromJson(map);
  }

  @override
  Future<CreatePrivateChatResultDto> createPrivateChat({
    required String appUserId,
    required String partnerId,
  }) async {
    final response = await _client.rpc(
      'create_private_chat_v1',
      params: {'p_user_id': appUserId, 'p_partner_id': partnerId},
    );
    return CreatePrivateChatResultDto.fromJson(_asMap(response));
  }

  @override
  Future<CanCreatePrivateChatDto> canCreatePrivateChat({
    required String appUserId,
    required String partnerId,
  }) async {
    final response = await _client.rpc(
      'can_create_private_chat_v1',
      params: {'p_user_id': appUserId, 'p_partner_id': partnerId},
    );
    return CanCreatePrivateChatDto.fromJson(_asMap(response));
  }

  @override
  Future<SentPrivateChatMessageDto> sendMessage({
    required String appUserId,
    required String chatId,
    required String text,
    String? clientNonce,
  }) async {
    final response = await _client.rpc(
      'send_private_chat_message_v1',
      params: {
        'p_user_id': appUserId,
        'p_chat_id': chatId,
        'p_text': text,
        if (clientNonce != null) 'p_client_nonce': clientNonce,
      },
    );
    return SentPrivateChatMessageDto.fromJson(_asMap(response));
  }

  @override
  Future<void> markChatRead({
    required String appUserId,
    required String chatId,
    required int readThroughSeq,
  }) async {
    await _client.rpc(
      'mark_private_chat_read_v1',
      params: {
        'p_user_id': appUserId,
        'p_chat_id': chatId,
        'p_read_through_seq': readThroughSeq,
      },
    );
  }

  @override
  Future<bool> deletePrivateChat({
    required String appUserId,
    required String chatId,
  }) async {
    final response = await _client.rpc(
      'delete_private_chat_v1',
      params: {'p_user_id': appUserId, 'p_chat_id': chatId},
    );
    final map = _asMap(response);
    return map['ok'] == true;
  }

  @override
  Future<bool> deletePrivateChatAndBlock({
    required String appUserId,
    required String chatId,
  }) async {
    final response = await _client.rpc(
      'delete_private_chat_and_block_v1',
      params: {'p_user_id': appUserId, 'p_chat_id': chatId},
    );
    final map = _asMap(response);
    return map['ok'] == true;
  }

  @override
  Future<void> editMessage({
    required String appUserId,
    required String chatId,
    required String messageId,
    required String text,
  }) async {
    await _client.rpc(
      'edit_private_chat_message_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_chat_id': chatId,
        'p_message_id': messageId,
        'p_text': text,
      },
    );
  }

  @override
  Future<void> deleteMessageForAll({
    required String appUserId,
    required String chatId,
    required String messageId,
  }) async {
    await _client.rpc(
      'delete_private_chat_message_for_all_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_chat_id': chatId,
        'p_message_id': messageId,
      },
    );
  }

  @override
  Future<void> deleteMessageForMe({
    required String appUserId,
    required String chatId,
    required String messageId,
  }) async {
    await _client.rpc(
      'delete_private_chat_message_for_me_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_chat_id': chatId,
        'p_message_id': messageId,
      },
    );
  }

  @override
  Future<void> deleteMessagesBulk({
    required String appUserId,
    required String chatId,
    required List<String> messageIds,
    required String mode,
  }) async {
    await _client.rpc(
      'delete_private_chat_messages_bulk_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_chat_id': chatId,
        'p_message_ids': messageIds,
        'p_mode': mode,
      },
    );
  }
}
