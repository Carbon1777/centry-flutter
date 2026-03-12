class PlanChatSnapshotMessageDto {
  final String id;
  final String planId;
  final int roomSeq;
  final String authorAppUserId;
  final String authorDisplayName;
  final String text;
  final DateTime createdAt;
  final bool isMine;

  PlanChatSnapshotMessageDto({
    required this.id,
    required this.planId,
    required this.roomSeq,
    required this.authorAppUserId,
    required this.authorDisplayName,
    required this.text,
    required this.createdAt,
    required this.isMine,
  });

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  factory PlanChatSnapshotMessageDto.fromJson(Map<String, dynamic> json) {
    return PlanChatSnapshotMessageDto(
      id: (json['id'] ?? '').toString(),
      planId: (json['plan_id'] ?? '').toString(),
      roomSeq: _asInt(json['room_seq']),
      authorAppUserId: (json['author_app_user_id'] ?? '').toString(),
      authorDisplayName: (json['author_display_name'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      createdAt: DateTime.parse((json['created_at'] ?? '').toString()),
      isMine: (json['is_mine'] as bool?) ?? false,
    );
  }
}

class PlanChatSnapshotDto {
  final String planId;
  final int roomMessageSeq;
  final int lastReadRoomSeq;
  final int unreadCount;
  final bool hasMore;
  final List<PlanChatSnapshotMessageDto> messages;

  const PlanChatSnapshotDto({
    required this.planId,
    required this.roomMessageSeq,
    required this.lastReadRoomSeq,
    required this.unreadCount,
    required this.hasMore,
    required this.messages,
  });

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  factory PlanChatSnapshotDto.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? const []);
    return PlanChatSnapshotDto(
      planId: (json['plan_id'] ?? '').toString(),
      roomMessageSeq: _asInt(json['room_message_seq']),
      lastReadRoomSeq: _asInt(json['last_read_room_seq']),
      unreadCount: _asInt(json['unread_count']),
      hasMore: (json['has_more'] as bool?) ?? false,
      messages: rawMessages
          .map((e) => PlanChatSnapshotMessageDto.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

class PlanChatBadgeItemDto {
  final String planId;
  final int unreadCount;
  final bool hasUnread;

  const PlanChatBadgeItemDto({
    required this.planId,
    required this.unreadCount,
    required this.hasUnread,
  });

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  factory PlanChatBadgeItemDto.fromJson(Map<String, dynamic> json) {
    final unreadCount = _asInt(json['unread_count']);
    return PlanChatBadgeItemDto(
      planId: (json['plan_id'] ?? '').toString(),
      unreadCount: unreadCount,
      hasUnread: (json['has_unread'] as bool?) ?? unreadCount > 0,
    );
  }
}

class PlanChatBadgesDto {
  final bool hasAnyUnread;
  final int unreadPlansCount;
  final List<PlanChatBadgeItemDto> items;

  const PlanChatBadgesDto({
    required this.hasAnyUnread,
    required this.unreadPlansCount,
    required this.items,
  });

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? fallback;
  }

  factory PlanChatBadgesDto.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List<dynamic>? ?? const []);
    return PlanChatBadgesDto(
      hasAnyUnread: (json['has_any_unread'] as bool?) ?? false,
      unreadPlansCount: _asInt(json['unread_plans_count']),
      items: rawItems
          .map((e) => PlanChatBadgeItemDto.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}
