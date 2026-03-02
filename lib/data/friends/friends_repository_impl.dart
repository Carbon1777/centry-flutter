import 'package:supabase_flutter/supabase_flutter.dart';

import 'accept_friend_result_dto.dart';
import 'friend_dto.dart';
import 'friend_request_result_dto.dart';
import 'friends_repository.dart';

class FriendsRepositoryImpl implements FriendsRepository {
  final SupabaseClient _client;

  FriendsRepositoryImpl(this._client);

  @override
  Future<List<FriendDto>> listMyFriends({
    required String appUserId,
  }) async {
    final response = await _client.rpc(
      'list_my_friends_v2',
      params: {
        'p_user_id': appUserId,
      },
    );

    final items = (response as List<dynamic>? ?? []);
    return items
        .map((e) => FriendDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<FriendRequestResultDto> requestFriendByPublicId({
    required String appUserId,
    required String targetPublicId,
  }) async {
    final response = await _client.rpc(
      'request_friend_by_public_id_v2',
      params: {
        'p_user_id': appUserId,
        'p_target_public_id': targetPublicId,
      },
    );

    // returns TABLE => PostgREST returns a list with one row
    final rows = (response as List<dynamic>? ?? []);
    final row =
        rows.isNotEmpty ? rows.first as Map<String, dynamic> : <String, dynamic>{};
    return FriendRequestResultDto.fromJson(row);
  }

  @override
  Future<AcceptFriendResultDto> acceptFriendRequest({
    required String appUserId,
    required String requestId,
  }) async {
    final response = await _client.rpc(
      'accept_friend_request_v2',
      params: {
        'p_user_id': appUserId,
        'p_request_id': requestId,
      },
    );

    final rows = (response as List<dynamic>? ?? []);
    final row =
        rows.isNotEmpty ? rows.first as Map<String, dynamic> : <String, dynamic>{};
    return AcceptFriendResultDto.fromJson(row);
  }

  @override
  Future<void> upsertFriendNote({
    required String appUserId,
    required String friendUserId,
    required String note,
  }) async {
    await _client.rpc(
      'upsert_friend_note_v2',
      params: {
        'p_user_id': appUserId,
        'p_friend_user_id': friendUserId,
        'p_note': note,
      },
    );
  }

  @override
  Future<void> removeFriend({
    required String appUserId,
    required String friendUserId,
  }) async {
    await _client.rpc(
      'remove_friend_v2',
      params: {
        'p_user_id': appUserId,
        'p_friend_user_id': friendUserId,
      },
    );
  }
}
