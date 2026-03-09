import '../places/place_dto.dart';

class PlanDetailsDto {
  final PlanCoreDto plan;

  /// Participants (без owner), как пришло с сервера
  final List<PlanMemberDto> members;

  /// Owner section (закреплённый сверху), как пришло с сервера
  final PlanMemberDto? ownerMember;

  /// Legacy list: оставляем для обратной совместимости со старым UI.
  /// Если сервер уже не отдаёт `date_candidates`, наполняем из `date_voting.candidates`.
  final List<DateCandidateDto> dateCandidates;

  /// Новый server-first snapshot блока голосования по датам.
  final PlanDateVotingDto dateVoting;

  final List<PlaceCandidateDto> placeCandidates;
  final List<PlanChatMessageDto> chat;

  PlanDetailsDto({
    required this.plan,
    required this.members,
    required this.ownerMember,
    required this.dateCandidates,
    required this.dateVoting,
    required this.placeCandidates,
    required this.chat,
  });

  factory PlanDetailsDto.fromJson(Map<String, dynamic> json) {
    final plan = PlanCoreDto.fromJson(json['plan'] as Map<String, dynamic>);

    final legacyDateCandidates =
        (json['date_candidates'] as List<dynamic>? ?? [])
            .map((e) => DateCandidateDto.fromJson(e as Map<String, dynamic>))
            .toList();

    final rawDateVoting = json['date_voting'];
    final dateVoting = rawDateVoting is Map<String, dynamic>
        ? PlanDateVotingDto.fromJson(rawDateVoting)
        : rawDateVoting is Map
            ? PlanDateVotingDto.fromJson(
                Map<String, dynamic>.from(rawDateVoting),
              )
            : PlanDateVotingDto.fromLegacy(
                votingDeadlineAt: plan.votingDeadlineAt,
                decidedDateAt: plan.decidedDateAt,
                legacyCandidates: legacyDateCandidates,
              );

    final effectiveDateCandidates = legacyDateCandidates.isNotEmpty
        ? legacyDateCandidates
        : dateVoting.candidates
            .map(DateCandidateDto.fromVotingCandidate)
            .toList();

    return PlanDetailsDto(
      plan: plan,
      members: (json['members'] as List<dynamic>? ?? [])
          .map((e) => PlanMemberDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      ownerMember: (json['owner_member'] is Map<String, dynamic>)
          ? PlanMemberDto.fromJson(json['owner_member'] as Map<String, dynamic>)
          : (json['owner_member'] is Map
              ? PlanMemberDto.fromJson(
                  Map<String, dynamic>.from(json['owner_member'] as Map),
                )
              : null),
      dateCandidates: effectiveDateCandidates,
      dateVoting: dateVoting,
      placeCandidates: (json['place_candidates'] as List<dynamic>? ?? [])
          .map((e) => PlaceCandidateDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      chat: (json['chat'] as List<dynamic>? ?? [])
          .map((e) => PlanChatMessageDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'y';
  }
  return false;
}

int _asInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

String _asString(dynamic v, {String fallback = ''}) {
  if (v == null) return fallback;
  return v.toString();
}

DateTime? _asDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/* ===================== PLAN CORE ===================== */

class PlanCoreDto {
  final String id;
  final String title;
  final String? description;
  final String role;
  final String status;

  final DateTime? votingDeadlineAt;
  final DateTime? eventAt;

  final String? decidedPlaceId;
  final DateTime? decidedDateAt;
  final DateTime? tieResolutionDeadlineAt;

  final bool visibleInFeed;
  final bool archived;

  /// server-first count (owner включён)
  final int membersCount;

  /// server-first permission: показывать ли кнопку "Добавить участника"
  final bool canAddMembers;

  final DateTime createdAt;
  final DateTime updatedAt;

  final bool canEditTitle;
  final bool canEditDescription;
  final bool canEditDeadline;
  final bool canUpdateVisibility;
  final bool canDeletePlan;
  final bool canLeavePlan;

  PlanCoreDto({
    required this.id,
    required this.title,
    required this.description,
    required this.role,
    required this.status,
    required this.votingDeadlineAt,
    required this.eventAt,
    required this.decidedPlaceId,
    required this.decidedDateAt,
    required this.tieResolutionDeadlineAt,
    required this.visibleInFeed,
    required this.archived,
    required this.membersCount,
    required this.canAddMembers,
    required this.createdAt,
    required this.updatedAt,
    required this.canEditTitle,
    required this.canEditDescription,
    required this.canEditDeadline,
    required this.canUpdateVisibility,
    required this.canDeletePlan,
    required this.canLeavePlan,
  });

  factory PlanCoreDto.fromJson(Map<String, dynamic> json) {
    return PlanCoreDto(
      id: _asString(json['id']),
      title: _asString(json['title']),
      description: json['description']?.toString(),
      role: _asString(json['role']),
      status: _asString(json['status']),
      votingDeadlineAt: _asDateTime(json['voting_deadline_at']),
      eventAt: _asDateTime(json['event_at']),
      decidedPlaceId: json['decided_place_id']?.toString(),
      decidedDateAt: _asDateTime(json['decided_date_at']),
      tieResolutionDeadlineAt: _asDateTime(json['tie_resolution_deadline_at']),
      visibleInFeed: _asBool(json['visible_in_feed']),
      archived: _asBool(json['archived']),
      membersCount: _asInt(json['members_count']),
      canAddMembers: _asBool(json['can_add_members']),
      createdAt: DateTime.parse(_asString(json['created_at'])),
      updatedAt: DateTime.parse(_asString(json['updated_at'])),
      canEditTitle: _asBool(json['can_edit_title']),
      canEditDescription: _asBool(json['can_edit_description']),
      canEditDeadline: _asBool(json['can_edit_deadline']),
      canUpdateVisibility: _asBool(json['can_update_visibility']),
      canDeletePlan: _asBool(json['can_delete_plan']),
      canLeavePlan: _asBool(json['can_leave_plan']),
    );
  }
}

/* ===================== MEMBERS ===================== */

class PlanMemberDto {
  final String appUserId;
  final String nickname;
  final String publicId;
  final String role;
  final DateTime? joinedAt;

  /// server-first UI flags
  ///
  /// canAddFriend: видимость иконки Add friend (сервер решает).
  /// canRemoveMember: видимость иконки удаления участника (сервер решает).
  final bool canAddFriend;
  final bool canRemoveMember;

  /// server-first: backend must provide this
  /// true when member.app_user_id == p_app_user_id in get_plan_details_v1
  final bool isMe;

  /// server-first relationship flags (relative to текущему пользователю)
  /// - isFriend: уже друзья (иконки Add friend быть не должно)
  /// - hasPendingFriendRequest: есть активный pending friend request (иконка есть, но disabled)
  ///
  /// ВАЖНО: пока сервер не отдаёт эти поля, они по дефолту false и ничего не ломают.
  final bool isFriend;
  final bool hasPendingFriendRequest;

  PlanMemberDto({
    required this.appUserId,
    required this.nickname,
    required this.publicId,
    required this.role,
    required this.joinedAt,
    required this.canAddFriend,
    required this.canRemoveMember,
    required this.isMe,
    this.isFriend = false,
    this.hasPendingFriendRequest = false,
  });

  factory PlanMemberDto.fromJson(Map<String, dynamic> json) {
    return PlanMemberDto(
      appUserId: _asString(json['app_user_id']),
      nickname: _asString(json['nickname']),
      publicId: _asString(json['public_id']),
      role: _asString(json['role']),
      joinedAt: _asDateTime(json['joined_at']),
      canAddFriend: _asBool(json['can_add_friend']),
      canRemoveMember: _asBool(json['can_remove_member']),
      isMe: _asBool(json['is_me']),
      isFriend: _asBool(json['is_friend']),
      hasPendingFriendRequest: _asBool(
        json['has_pending_friend_request'] ??
            json['pending_friend_request'] ??
            json['is_friend_request_pending'] ??
            json['friend_request_pending'],
      ),
    );
  }
}

/* ===================== DATE VOTING ===================== */

class PlanDateVotingDto {
  final DateTime? votingDeadlineAt;
  final bool isVotingActive;
  final bool canAddCandidate;
  final int freeSlotsCount;
  final int candidatesCount;
  final bool ownerChoiceModeActive;
  final String? finalWinnerCandidateId;
  final bool noWinnerYet;
  final int hoursLeftToDeadline;
  final bool postDeadlineGraceActive;
  final List<PlanDateVotingCandidateDto> candidates;

  PlanDateVotingDto({
    required this.votingDeadlineAt,
    required this.isVotingActive,
    required this.canAddCandidate,
    required this.freeSlotsCount,
    required this.candidatesCount,
    required this.ownerChoiceModeActive,
    required this.finalWinnerCandidateId,
    required this.noWinnerYet,
    required this.hoursLeftToDeadline,
    required this.postDeadlineGraceActive,
    required this.candidates,
  });

  factory PlanDateVotingDto.fromJson(Map<String, dynamic> json) {
    return PlanDateVotingDto(
      votingDeadlineAt: _asDateTime(json['voting_deadline_at']),
      isVotingActive: _asBool(json['is_voting_active']),
      canAddCandidate: _asBool(json['can_add_candidate']),
      freeSlotsCount: _asInt(json['free_slots_count']),
      candidatesCount: _asInt(json['candidates_count']),
      ownerChoiceModeActive: _asBool(json['owner_choice_mode_active']),
      finalWinnerCandidateId: json['final_winner_candidate_id']?.toString(),
      noWinnerYet: _asBool(json['no_winner_yet']),
      hoursLeftToDeadline: _asInt(json['hours_left_to_deadline']),
      postDeadlineGraceActive: _asBool(json['post_deadline_grace_active']),
      candidates: (json['candidates'] as List<dynamic>? ?? [])
          .map(
            (e) => PlanDateVotingCandidateDto.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }

  factory PlanDateVotingDto.fromLegacy({
    required DateTime? votingDeadlineAt,
    required DateTime? decidedDateAt,
    required List<DateCandidateDto> legacyCandidates,
  }) {
    final winnerId = decidedDateAt?.toIso8601String();
    final mappedCandidates = legacyCandidates
        .asMap()
        .entries
        .map(
          (entry) => PlanDateVotingCandidateDto(
            candidateId: entry.value.dateAt.toIso8601String(),
            dateTime: entry.value.dateAt,
            weekdayRu: '',
            dateLabel: '',
            timeLabel: '',
            votesCount: entry.value.votesCount,
            createdByUserId: '',
            createdByCurrentUser: false,
            isUserVotedForThis: entry.value.myVote,
            isLeading: false,
            isWinner:
                decidedDateAt != null && entry.value.dateAt == decidedDateAt,
            isDimmed: false,
            isOwnerPriorityChoice: false,
            isAvailableForOwnerChoiceNow: false,
            canVote: false,
            canUnvote: false,
            canDelete: false,
            canClearOwnerPriority: false,
            positionIndex: entry.key,
          ),
        )
        .toList();

    return PlanDateVotingDto(
      votingDeadlineAt: votingDeadlineAt,
      isVotingActive: false,
      canAddCandidate: false,
      freeSlotsCount:
          legacyCandidates.length >= 3 ? 0 : (3 - legacyCandidates.length),
      candidatesCount: legacyCandidates.length,
      ownerChoiceModeActive: false,
      finalWinnerCandidateId: winnerId,
      noWinnerYet: decidedDateAt == null,
      hoursLeftToDeadline: 0,
      postDeadlineGraceActive: false,
      candidates: mappedCandidates,
    );
  }
}

class PlanDateVotingCandidateDto {
  final String candidateId;
  final DateTime dateTime;
  final String weekdayRu;
  final String dateLabel;
  final String timeLabel;
  final int votesCount;
  final String createdByUserId;
  final bool createdByCurrentUser;
  final bool isUserVotedForThis;
  final bool isLeading;
  final bool isWinner;
  final bool isDimmed;
  final bool isOwnerPriorityChoice;
  final bool isAvailableForOwnerChoiceNow;
  final bool canVote;
  final bool canUnvote;
  final bool canDelete;
  final bool canClearOwnerPriority;
  final int positionIndex;

  PlanDateVotingCandidateDto({
    required this.candidateId,
    required this.dateTime,
    required this.weekdayRu,
    required this.dateLabel,
    required this.timeLabel,
    required this.votesCount,
    required this.createdByUserId,
    required this.createdByCurrentUser,
    required this.isUserVotedForThis,
    required this.isLeading,
    required this.isWinner,
    required this.isDimmed,
    required this.isOwnerPriorityChoice,
    required this.isAvailableForOwnerChoiceNow,
    required this.canVote,
    required this.canUnvote,
    required this.canDelete,
    required this.canClearOwnerPriority,
    required this.positionIndex,
  });

  factory PlanDateVotingCandidateDto.fromJson(Map<String, dynamic> json) {
    final dateTime = _asDateTime(json['datetime']) ??
        _asDateTime(json['date_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return PlanDateVotingCandidateDto(
      candidateId: _asString(
        json['candidate_id'],
        fallback: dateTime.toIso8601String(),
      ),
      dateTime: dateTime,
      weekdayRu: _asString(json['weekday_ru']),
      dateLabel: _asString(json['date_label']),
      timeLabel: _asString(json['time_label']),
      votesCount: _asInt(json['votes_count']),
      createdByUserId: _asString(json['created_by_user_id']),
      createdByCurrentUser: _asBool(json['created_by_current_user']),
      isUserVotedForThis: _asBool(json['is_user_voted_for_this']),
      isLeading: _asBool(json['is_leading']),
      isWinner: _asBool(json['is_winner']),
      isDimmed: _asBool(json['is_dimmed']),
      isOwnerPriorityChoice: _asBool(json['is_owner_priority_choice']),
      isAvailableForOwnerChoiceNow: _asBool(
        json['is_available_for_owner_choice_now'],
      ),
      canVote: _asBool(json['can_vote']),
      canUnvote: _asBool(json['can_unvote']),
      canDelete: _asBool(json['can_delete']),
      canClearOwnerPriority: _asBool(json['can_clear_owner_priority']),
      positionIndex: _asInt(json['position_index']),
    );
  }
}

/* ===================== LEGACY DATE CANDIDATES ===================== */

class DateCandidateDto {
  final DateTime dateAt;
  final int votesCount;
  final bool myVote;

  DateCandidateDto({
    required this.dateAt,
    required this.votesCount,
    required this.myVote,
  });

  factory DateCandidateDto.fromJson(Map<String, dynamic> json) {
    return DateCandidateDto(
      dateAt: DateTime.parse(_asString(json['date_at'])),
      votesCount: _asInt(json['votes_count']),
      myVote: _asBool(json['my_vote']),
    );
  }

  factory DateCandidateDto.fromVotingCandidate(
    PlanDateVotingCandidateDto candidate,
  ) {
    return DateCandidateDto(
      dateAt: candidate.dateTime,
      votesCount: candidate.votesCount,
      myVote: candidate.isUserVotedForThis,
    );
  }
}

/* ===================== PLACE CANDIDATES ===================== */

class PlaceCandidateDto {
  final String candidateId;
  final String sourceKind;
  final String? placeId;
  final String? placeSubmissionId;

  final String title;
  final String type;
  final String address;
  final String? cityId;
  final String cityName;
  final String? areaId;
  final String? areaName;

  final double? lat;
  final double? lng;
  final double? distanceM;

  final String? previewMediaUrl;
  final String? previewStorageKey;
  final bool previewIsPlaceholder;
  final String? metroName;
  final int? metroDistanceM;
  final double? rating;
  final int likesCount;
  final int dislikesCount;
  final String? websiteUrl;

  final String? moderationStatus;
  final bool isPendingModeration;
  final bool isRejected;
  final int votesCount;
  final String createdByUserId;
  final bool createdByCurrentUser;
  final bool isUserVotedForThis;
  final bool isLeading;
  final bool isWinner;
  final bool isDimmed;
  final bool canVote;
  final bool canUnvote;
  final bool canDelete;
  final int positionIndex;

  PlaceCandidateDto({
    required this.candidateId,
    required this.sourceKind,
    required this.placeId,
    required this.placeSubmissionId,
    required this.title,
    required this.type,
    required this.address,
    required this.cityId,
    required this.cityName,
    required this.areaId,
    required this.areaName,
    required this.lat,
    required this.lng,
    required this.distanceM,
    required this.previewMediaUrl,
    required this.previewStorageKey,
    required this.previewIsPlaceholder,
    required this.metroName,
    required this.metroDistanceM,
    required this.rating,
    required this.likesCount,
    required this.dislikesCount,
    required this.websiteUrl,
    required this.moderationStatus,
    required this.isPendingModeration,
    required this.isRejected,
    required this.votesCount,
    required this.createdByUserId,
    required this.createdByCurrentUser,
    required this.isUserVotedForThis,
    required this.isLeading,
    required this.isWinner,
    required this.isDimmed,
    required this.canVote,
    required this.canUnvote,
    required this.canDelete,
    required this.positionIndex,
  });

  bool get isCorePlace => sourceKind == 'CORE' && placeId != null && lat != null && lng != null;
  bool get isSubmissionPlace => sourceKind == 'SUBMISSION';

  PlaceDto? toPlaceDto() {
    if (!isCorePlace) return null;

    return PlaceDto(
      id: placeId!,
      title: title,
      type: type,
      address: address,
      cityId: cityId ?? '',
      cityName: cityName,
      areaId: areaId,
      areaName: areaName,
      lat: lat!,
      lng: lng!,
      distanceM: distanceM,
      previewMediaUrl: previewMediaUrl,
      previewStorageKey: previewStorageKey,
      previewIsPlaceholder: previewIsPlaceholder,
      metroName: metroName,
      metroDistanceM: metroDistanceM,
      rating: rating,
      likesCount: likesCount,
      dislikesCount: dislikesCount,
      websiteUrl: websiteUrl,
    );
  }

  factory PlaceCandidateDto.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? asIntNullable(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return PlaceCandidateDto(
      candidateId: _asString(json['candidate_id']),
      sourceKind: _asString(json['source_kind']),
      placeId: json['place_id']?.toString(),
      placeSubmissionId: json['place_submission_id']?.toString(),
      title: _asString(json['title']),
      type: _asString(json['type']),
      address: _asString(json['address']),
      cityId: json['city_id']?.toString(),
      cityName: _asString(json['city_name']),
      areaId: json['area_id']?.toString(),
      areaName: json['area_name']?.toString(),
      lat: asDouble(json['lat']),
      lng: asDouble(json['lng']),
      distanceM: asDouble(json['distance_m']),
      previewMediaUrl: json['preview_media_url']?.toString(),
      previewStorageKey: json['preview_storage_key']?.toString(),
      previewIsPlaceholder: _asBool(json['preview_is_placeholder']),
      metroName: json['metro_name']?.toString(),
      metroDistanceM: asIntNullable(json['metro_distance_m']),
      rating: asDouble(json['rating']),
      likesCount: _asInt(json['likes_count']),
      dislikesCount: _asInt(json['dislikes_count']),
      websiteUrl: json['website_url']?.toString(),
      moderationStatus: json['moderation_status']?.toString(),
      isPendingModeration: _asBool(json['is_pending_moderation']),
      isRejected: _asBool(json['is_rejected']),
      votesCount: _asInt(json['votes_count']),
      createdByUserId: _asString(json['created_by_user_id']),
      createdByCurrentUser: _asBool(json['created_by_current_user']),
      isUserVotedForThis: _asBool(json['is_user_voted_for_this']),
      isLeading: _asBool(json['is_leading']),
      isWinner: _asBool(json['is_winner']),
      isDimmed: _asBool(json['is_dimmed']),
      canVote: _asBool(json['can_vote']),
      canUnvote: _asBool(json['can_unvote']),
      canDelete: _asBool(json['can_delete']),
      positionIndex: _asInt(json['position_index']),
    );
  }
}

/* ===================== CHAT ===================== */

class PlanChatMessageDto {
  final String id;
  final String authorAppUserId;
  final String text;
  final DateTime createdAt;

  PlanChatMessageDto({
    required this.id,
    required this.authorAppUserId,
    required this.text,
    required this.createdAt,
  });

  factory PlanChatMessageDto.fromJson(Map<String, dynamic> json) {
    return PlanChatMessageDto(
      id: _asString(json['id']),
      authorAppUserId: _asString(json['author_app_user_id']),
      text: _asString(json['text']),
      createdAt: DateTime.parse(_asString(json['created_at'])),
    );
  }
}
