import 'package:supabase_flutter/supabase_flutter.dart';

import 'friends_repository.dart';
import 'friend_dto.dart';
import 'friend_request_result_dto.dart';
import 'accept_friend_result_dto.dart';

class FriendsRepositoryImpl implements FriendsRepository {
  final SupabaseClient _client;

  FriendsRepositoryImpl(this._client);

  // ===========================================================
  // INTERNAL: ensure device is registered (idempotent on server)
  // ===========================================================
  Future<void> _ensureDeviceRegistered({
    required String appUserId,
    required String deviceSecret,
  }) async {
    await _client.rpc(
      'register_device_secret_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
      },
    );
  }

  @override
  Future<List<FriendDto>> listMyFriends({
    required String appUserId,
    required String deviceSecret,
  }) async {
    await _ensureDeviceRegistered(appUserId: appUserId, deviceSecret: deviceSecret);

    final response = await _client.rpc(
      'list_my_friends_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
      },
    );

    final items = (response as List<dynamic>? ?? []);
    return items.map((e) => FriendDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<FriendRequestResultDto> requestFriendByPublicId({
    required String appUserId,
    required String deviceSecret,
    required String targetPublicId,
  }) async {
    await _ensureDeviceRegistered(appUserId: appUserId, deviceSecret: deviceSecret);

    final response = await _client.rpc(
      'request_friend_by_public_id_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
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
    required String deviceSecret,
    required String requestId,
  }) async {
    await _ensureDeviceRegistered(appUserId: appUserId, deviceSecret: deviceSecret);

    final response = await _client.rpc(
      'accept_friend_request_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
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
    required String deviceSecret,
    required String friendUserId,
    required String note,
  }) async {
    await _ensureDeviceRegistered(appUserId: appUserId, deviceSecret: deviceSecret);

    await _client.rpc(
      'upsert_friend_note_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
        'p_friend_user_id': friendUserId,
        'p_note': note,
      },
    );
  }

  @override
  Future<void> removeFriend({
    required String appUserId,
    required String deviceSecret,
    required String friendUserId,
  }) async {
    await _ensureDeviceRegistered(appUserId: appUserId, deviceSecret: deviceSecret);

    await _client.rpc(
      'remove_friend_v1',
      params: {
        'p_user_id': appUserId,
        'p_device_secret': deviceSecret,
        'p_friend_user_id': friendUserId,
      },
    );
  }
}
