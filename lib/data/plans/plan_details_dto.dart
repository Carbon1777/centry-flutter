class PlanDetailsDto {
  final PlanCoreDto plan;

  /// Participants (без owner), как пришло с сервера
  final List<PlanMemberDto> members;

  /// Owner section (закреплённый сверху), как пришло с сервера
  final PlanMemberDto? ownerMember;

  final List<DateCandidateDto> dateCandidates;
  final List<PlaceCandidateDto> placeCandidates;
  final List<PlanChatMessageDto> chat;

  PlanDetailsDto({
    required this.plan,
    required this.members,
    required this.ownerMember,
    required this.dateCandidates,
    required this.placeCandidates,
    required this.chat,
  });

  factory PlanDetailsDto.fromJson(Map<String, dynamic> json) {
    return PlanDetailsDto(
      plan: PlanCoreDto.fromJson(json['plan'] as Map<String, dynamic>),
      members: (json['members'] as List<dynamic>? ?? [])
          .map((e) => PlanMemberDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      ownerMember: (json['owner_member'] is Map<String, dynamic>)
          ? PlanMemberDto.fromJson(json['owner_member'] as Map<String, dynamic>)
          : null,
      dateCandidates: (json['date_candidates'] as List<dynamic>? ?? [])
          .map((e) => DateCandidateDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      placeCandidates: (json['place_candidates'] as List<dynamic>? ?? [])
          .map((e) => PlaceCandidateDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      chat: (json['chat'] as List<dynamic>? ?? [])
          .map((e) => PlanChatMessageDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
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

  /// ✅ server-first permission: показывать ли кнопку "Добавить участника"
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

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory PlanCoreDto.fromJson(Map<String, dynamic> json) {
    return PlanCoreDto(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      role: json['role'],
      status: json['status'],
      votingDeadlineAt: _asDate(json['voting_deadline_at']),
      eventAt: _asDate(json['event_at']),
      decidedPlaceId: json['decided_place_id'],
      decidedDateAt: _asDate(json['decided_date_at']),
      tieResolutionDeadlineAt: _asDate(json['tie_resolution_deadline_at']),
      visibleInFeed: json['visible_in_feed'] ?? false,
      archived: json['archived'] ?? false,
      membersCount: json['members_count'] ?? 0,
      canAddMembers: json['can_add_members'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      canEditTitle: json['can_edit_title'] ?? false,
      canEditDescription: json['can_edit_description'] ?? false,
      canEditDeadline: json['can_edit_deadline'] ?? false,
      canUpdateVisibility: json['can_update_visibility'] ?? false,
      canDeletePlan: json['can_delete_plan'] ?? false,
      canLeavePlan: json['can_leave_plan'] ?? false,
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
  final bool canAddFriend;
  final bool canRemoveMember;

  /// ✅ server-first: backend must provide this
  /// true when member.app_user_id == p_app_user_id in get_plan_details_v1
  final bool isMe;

  PlanMemberDto({
    required this.appUserId,
    required this.nickname,
    required this.publicId,
    required this.role,
    required this.joinedAt,
    required this.canAddFriend,
    required this.canRemoveMember,
    required this.isMe,
  });

  factory PlanMemberDto.fromJson(Map<String, dynamic> json) {
    return PlanMemberDto(
      appUserId: json['app_user_id'],
      nickname: json['nickname'],
      publicId: json['public_id'],
      role: json['role'],
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'])
          : null,
      canAddFriend: json['can_add_friend'] ?? false,
      canRemoveMember: json['can_remove_member'] ?? false,
      isMe: json['is_me'] ?? false,
    );
  }
}

/* ===================== DATE CANDIDATES ===================== */

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
      dateAt: DateTime.parse(json['date_at']),
      votesCount: json['votes_count'] ?? 0,
      myVote: json['my_vote'] ?? false,
    );
  }
}

/* ===================== PLACE CANDIDATES ===================== */

class PlaceCandidateDto {
  final String placeId;
  final int votesCount;
  final bool myVote;

  PlaceCandidateDto({
    required this.placeId,
    required this.votesCount,
    required this.myVote,
  });

  factory PlaceCandidateDto.fromJson(Map<String, dynamic> json) {
    return PlaceCandidateDto(
      placeId: json['place_id'],
      votesCount: json['votes_count'] ?? 0,
      myVote: json['my_vote'] ?? false,
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
      id: json['id'],
      authorAppUserId: json['author_app_user_id'],
      text: json['text'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
