import 'package:supabase_flutter/supabase_flutter.dart';

import 'attention_sign_dto.dart';
import 'attention_signs_repository.dart';

class AttentionSignsRepositoryImpl implements AttentionSignsRepository {
  final SupabaseClient _client;

  AttentionSignsRepositoryImpl(this._client);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Expected map response, got: $value');
  }

  @override
  Future<AttentionSignBoxDto> getMyBox({required String appUserId}) async {
    final response = await _client.rpc(
      'get_my_attention_sign_box_v1',
      params: {'p_user_id': appUserId},
    );
    return AttentionSignBoxDto.fromJson(_asMap(response));
  }

  @override
  Future<SendAttentionSignResultDto> sendSign({
    required String appUserId,
    required String targetUserId,
    required String dailySignId,
  }) async {
    final response = await _client.rpc(
      'send_attention_sign_v1',
      params: {
        'p_user_id': appUserId,
        'p_target_user_id': targetUserId,
        'p_daily_sign_id': dailySignId,
      },
    );
    return SendAttentionSignResultDto.fromJson(_asMap(response));
  }

  @override
  Future<bool> acceptSign({
    required String appUserId,
    required String submissionId,
  }) async {
    final response = await _client.rpc(
      'accept_attention_sign_v1',
      params: {'p_user_id': appUserId, 'p_submission_id': submissionId},
    );
    final map = _asMap(response);
    return map['ok'] == true;
  }

  @override
  Future<bool> declineSign({
    required String appUserId,
    required String submissionId,
  }) async {
    final response = await _client.rpc(
      'decline_attention_sign_v1',
      params: {'p_user_id': appUserId, 'p_submission_id': submissionId},
    );
    final map = _asMap(response);
    return map['ok'] == true;
  }

  @override
  Future<String?> useFriendInviteRight({
    required String appUserId,
    required String submissionId,
  }) async {
    final response = await _client.rpc(
      'use_friend_invite_right_v1',
      params: {'p_user_id': appUserId, 'p_submission_id': submissionId},
    );
    final map = _asMap(response);
    if (map['ok'] == true) return map['target_user_id'] as String?;
    return null;
  }

  @override
  Future<bool> useFriendInviteRightAndRequest({
    required String appUserId,
    required String submissionId,
  }) async {
    final response = await _client.rpc(
      'use_friend_invite_right_and_request_v1',
      params: {'p_user_id': appUserId, 'p_submission_id': submissionId},
    );
    final map = _asMap(response);
    return map['ok'] == true;
  }
}
