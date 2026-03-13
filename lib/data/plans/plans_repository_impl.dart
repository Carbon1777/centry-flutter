import 'package:supabase_flutter/supabase_flutter.dart';

import 'plan_chat_dto.dart';
import 'plan_details_dto.dart';
import 'plan_summary_dto.dart';
import 'plans_repository.dart';

class PlansRepositoryImpl implements PlansRepository {
  final SupabaseClient _client;

  PlansRepositoryImpl(this._client);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Expected map response, got: $value');
  }

  /* ===================== READ ===================== */

  @override
  Future<List<PlanSummaryDto>> getMyPlans({
    required String appUserId,
  }) async {
    final response = await _client.rpc(
      'get_my_plans_v1',
      params: {'p_app_user_id': appUserId},
    );

    final items = (response['items'] as List<dynamic>? ?? []);
    return items.map((e) => PlanSummaryDto.fromJson(e)).toList();
  }

  @override
  Future<List<PlanSummaryDto>> getMyPlansArchive({
    required String appUserId,
  }) async {
    final response = await _client.rpc(
      'get_my_plans_archive_v1',
      params: {'p_app_user_id': appUserId},
    );

    final items = (response['items'] as List<dynamic>? ?? []);
    return items.map((e) => PlanSummaryDto.fromJson(e)).toList();
  }

  @override
  Future<PlanDetailsDto> getPlanDetails({
    required String appUserId,
    required String planId,
  }) async {
    final ctx = await _client.rpc('debug_rpc_context_v1');
    print('RPC CTX: $ctx');

    final response = await _client.rpc(
      'get_plan_details_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );

    final members =
        (response is Map<String, dynamic>) ? response['members'] : null;
    print('RPC get_plan_details_v1 members raw: $members');
    print(
      'RPC get_plan_details_v1 members count: ${members is List ? members.length : 'not-a-list'}',
    );

    return PlanDetailsDto.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<PlanChatSnapshotDto> getPlanChatSnapshot({
    required String appUserId,
    required String planId,
    int limit = 50,
    int? beforeRoomSeq,
  }) async {
    final response = await _client.rpc(
      'get_plan_chat_snapshot_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_limit': limit,
        'p_before_room_seq': beforeRoomSeq,
      },
    );

    return PlanChatSnapshotDto.fromJson(_asMap(response));
  }

  @override
  Future<PlanChatBadgesDto> getMyPlanChatBadges({
    required String appUserId,
    bool includeArchived = false,
  }) async {
    final response = await _client.rpc(
      'get_my_plan_chat_badges_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_include_archived': includeArchived,
      },
    );

    return PlanChatBadgesDto.fromJson(_asMap(response));
  }

  @override
  Future<PlanChatSnapshotMessageDto> sendPlanChatMessage({
    required String appUserId,
    required String planId,
    required String text,
    String? clientNonce,
  }) async {
    final response = await _client.rpc(
      'send_plan_chat_message_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_text': text,
        'p_client_nonce': clientNonce,
      },
    );

    final map = _asMap(response);
    return PlanChatSnapshotMessageDto.fromJson(_asMap(map['message']));
  }

  @override
  Future<void> markPlanChatRead({
    required String appUserId,
    required String planId,
    required int readThroughRoomSeq,
  }) async {
    await _client.rpc(
      'mark_plan_chat_read_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_read_through_room_seq': readThroughRoomSeq,
      },
    );
  }

  /* ===================== CREATE ===================== */

  @override
  Future<String> createPlan({
    required String appUserId,
    required String title,
    required String description,
    required DateTime votingDeadlineAt,
    String? initialPlaceId,
  }) async {
    final response = await _client.rpc(
      'create_plan_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_title': title,
        'p_description': description,
        'p_voting_deadline_at': votingDeadlineAt.toUtc().toIso8601String(),
        'p_initial_place_id': initialPlaceId,
      },
    );

    if (response == null) {
      throw Exception('create_plan_v1 returned null');
    }

    return response as String;
  }

  /* ===================== UPDATE ===================== */

  @override
  Future<void> updatePlanVisibility({
    required String appUserId,
    required String planId,
    required bool visible,
  }) async {
    await _client.rpc(
      'update_plan_visibility_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_visible': visible,
      },
    );
  }

  @override
  Future<void> updatePlanTitle({
    required String appUserId,
    required String planId,
    required String title,
  }) async {
    await _client.rpc(
      'update_plan_title_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_title': title,
      },
    );
  }

  @override
  Future<void> updatePlanDescription({
    required String appUserId,
    required String planId,
    required String description,
  }) async {
    await _client.rpc(
      'update_plan_description_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_description': description,
      },
    );
  }

  @override
  Future<void> updatePlanDeadline({
    required String appUserId,
    required String planId,
    required DateTime votingDeadlineAt,
  }) async {
    await _client.rpc(
      'update_plan_deadline_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_voting_deadline_at': votingDeadlineAt.toUtc().toIso8601String(),
      },
    );
  }

  /* ===================== VOTES ===================== */

  @override
  Future<void> votePlanPlace({
    required String appUserId,
    required String planId,
    required String placeId,
  }) async {
    await _client.rpc(
      'vote_plan_place_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_place_id': placeId,
      },
    );
  }

  @override
  Future<void> votePlanPlaceSubmission({
    required String appUserId,
    required String planId,
    required String placeSubmissionId,
  }) async {
    await _client.rpc(
      'vote_plan_place_submission_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_place_submission_id': placeSubmissionId,
      },
    );
  }

  @override
  Future<void> unvotePlanPlace({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'unvote_plan_place_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  @override
  Future<void> votePlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  }) async {
    await _client.rpc(
      'vote_plan_date_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_date_at': dateAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> unvotePlanDate({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'unvote_plan_date_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  /* ===================== ADD / REMOVE ===================== */

  @override
  Future<void> addPlanPlace({
    required String appUserId,
    required String planId,
    required String placeId,
  }) async {
    await _client.rpc(
      'add_plan_place_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_place_id': placeId,
      },
    );
  }

  @override
  Future<void> removePlanPlace({
    required String appUserId,
    required String planId,
    String? placeId,
    String? placeSubmissionId,
  }) async {
    await _client.rpc(
      'remove_plan_place_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_place_id': placeId,
        'p_place_submission_id': placeSubmissionId,
      },
    );
  }

  @override
  Future<void> addPlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  }) async {
    await _client.rpc(
      'add_plan_date_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_date_at': dateAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> deletePlanDate({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  }) async {
    await _client.rpc(
      'delete_plan_date_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_date_at': dateAt.toUtc().toIso8601String(),
      },
    );
  }

  /* ===================== OWNER PRIORITY ===================== */

  @override
  Future<void> choosePlanDateOwnerPriority({
    required String appUserId,
    required String planId,
    required DateTime dateAt,
  }) async {
    await _client.rpc(
      'choose_plan_date_owner_priority_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_date_at': dateAt.toUtc().toIso8601String(),
      },
    );
  }

  @override
  Future<void> clearPlanDateOwnerPriority({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'clear_plan_date_owner_priority_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  @override
  Future<void> choosePlanPlaceOwnerPriority({
    required String appUserId,
    required String planId,
    String? placeId,
    String? placeSubmissionId,
  }) async {
    await _client.rpc(
      'choose_plan_place_owner_priority_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_place_id': placeId,
        'p_place_submission_id': placeSubmissionId,
      },
    );
  }

  @override
  Future<void> clearPlanPlaceOwnerPriority({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'clear_plan_place_owner_priority_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  /* ===================== MEMBERS ===================== */

  @override
  Future<void> leavePlan({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'leave_plan_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  @override
  Future<void> removeMember({
    required String ownerAppUserId,
    required String planId,
    required String memberAppUserId,
  }) async {
    await _client.rpc(
      'remove_plan_member_v1',
      params: {
        'p_owner_app_user_id': ownerAppUserId,
        'p_plan_id': planId,
        'p_member_app_user_id': memberAppUserId,
      },
    );
  }

  @override
  Future<void> addMemberByPublicId({
    required String appUserId,
    required String planId,
    required String publicId,
  }) async {
    await _client.rpc(
      'create_plan_internal_invite_by_public_id_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
        'p_public_id': publicId,
      },
    );
  }

  @override
  Future<void> deletePlan({
    required String appUserId,
    required String planId,
  }) async {
    await _client.rpc(
      'delete_plan_v1',
      params: {
        'p_owner_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );
  }

  /* ===================== INVITES ===================== */

  String _pickInviteShareText(dynamic response) {
    if (response is Map) {
      final map = Map<String, dynamic>.from(response);
      final shareText = (map['share_text'] ?? '').toString().trim();
      if (shareText.isNotEmpty) return shareText;

      final shareUrl = (map['share_url'] ?? '').toString().trim();
      if (shareUrl.isNotEmpty) return shareUrl;

      final token = (map['token'] ?? '').toString().trim();
      if (token.isNotEmpty) return token;

      return map.toString();
    }

    if (response is String) {
      return response.trim();
    }

    return response?.toString() ?? '';
  }

  @override
  Future<String> createInvite({
    required String appUserId,
    required String planId,
  }) async {
    final response = await _client.rpc(
      'create_plan_invite_v2',
      params: {
        'p_app_user_id': appUserId,
        'p_plan_id': planId,
      },
    );

    final shareText = _pickInviteShareText(response);
    if (shareText.isEmpty) {
      throw Exception('create_plan_invite_v2 returned empty payload');
    }

    return shareText;
  }

  @override
  Future<String> useInvite({
    required String appUserId,
    required String token,
  }) async {
    final response = await _client.rpc(
      'use_plan_invite_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_token': token,
      },
    );

    return response.toString();
  }
}
