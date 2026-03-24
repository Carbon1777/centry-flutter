// ---------------------------------------------------------------------------
// DTO для списка чатов
// ---------------------------------------------------------------------------

class PrivateChatListItemDto {
  final String chatId;
  final String partnerUserId;
  final int messageSeq;
  final DateTime? lastMessageAt;
  final int lastReadRoomSeq;
  final int unreadCount;
  final bool hasUnread;
  final DateTime createdAt;
  final String? lastMessageText;
  final bool lastMessageIsMine;

  const PrivateChatListItemDto({
    required this.chatId,
    required this.partnerUserId,
    required this.messageSeq,
    this.lastMessageAt,
    required this.lastReadRoomSeq,
    required this.unreadCount,
    required this.hasUnread,
    required this.createdAt,
    this.lastMessageText,
    this.lastMessageIsMine = false,
  });

  factory PrivateChatListItemDto.fromJson(Map<String, dynamic> j) =>
      PrivateChatListItemDto(
        chatId: j['chat_id'] as String,
        partnerUserId: j['partner_user_id'] as String,
        messageSeq: (j['message_seq'] as num).toInt(),
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.parse(j['last_message_at'] as String)
            : null,
        lastReadRoomSeq: (j['last_read_room_seq'] as num).toInt(),
        unreadCount: (j['unread_count'] as num).toInt(),
        hasUnread: j['has_unread'] as bool,
        createdAt: DateTime.parse(j['created_at'] as String),
        lastMessageText: j['last_message_text'] as String?,
        lastMessageIsMine: j['last_message_is_mine'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// DTO для badges (есть ли непрочитанные)
// ---------------------------------------------------------------------------

class PrivateChatBadgesDto {
  final bool hasUnread;

  const PrivateChatBadgesDto({required this.hasUnread});

  factory PrivateChatBadgesDto.fromJson(Map<String, dynamic> j) =>
      PrivateChatBadgesDto(hasUnread: j['has_unread'] as bool? ?? false);
}

// ---------------------------------------------------------------------------
// DTO сообщения
// ---------------------------------------------------------------------------

class PrivateChatMessageDto {
  final String id;
  final String chatId;
  final int roomSeq;
  final String authorAppUserId;
  final String text;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final DateTime? editedAt;
  final String messageKind;
  final bool isMine;

  bool get isTombstone => deletedAt != null || messageKind == 'TOMBSTONE';
  bool get isEdited => editedAt != null && !isTombstone;

  const PrivateChatMessageDto({
    required this.id,
    required this.chatId,
    required this.roomSeq,
    required this.authorAppUserId,
    required this.text,
    required this.createdAt,
    this.deletedAt,
    this.editedAt,
    required this.messageKind,
    required this.isMine,
  });

  factory PrivateChatMessageDto.fromJson(Map<String, dynamic> j) =>
      PrivateChatMessageDto(
        id: j['id'] as String,
        chatId: j['chat_id'] as String,
        roomSeq: (j['room_seq'] as num).toInt(),
        authorAppUserId: j['author_app_user_id'] as String,
        text: j['text'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        deletedAt: j['deleted_at'] != null
            ? DateTime.parse(j['deleted_at'] as String)
            : null,
        editedAt: j['edited_at'] != null
            ? DateTime.parse(j['edited_at'] as String)
            : null,
        messageKind: j['message_kind'] as String? ?? 'USER_TEXT',
        isMine: j['is_mine'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// DTO снапшота чата
// ---------------------------------------------------------------------------

class PrivateChatSnapshotDto {
  final String chatId;
  final String partnerUserId;
  final int roomMessageSeq;
  final int lastReadRoomSeq;
  final int unreadCount;
  final List<PrivateChatMessageDto> messages;
  final bool hasMore;
  final int? firstUnreadRoomSeq;

  const PrivateChatSnapshotDto({
    required this.chatId,
    required this.partnerUserId,
    required this.roomMessageSeq,
    required this.lastReadRoomSeq,
    required this.unreadCount,
    required this.messages,
    required this.hasMore,
    this.firstUnreadRoomSeq,
  });

  factory PrivateChatSnapshotDto.fromJson(Map<String, dynamic> j) =>
      PrivateChatSnapshotDto(
        chatId: j['chat_id'] as String,
        partnerUserId: j['partner_user_id'] as String,
        roomMessageSeq: (j['room_message_seq'] as num).toInt(),
        lastReadRoomSeq: (j['last_read_room_seq'] as num).toInt(),
        unreadCount: (j['unread_count'] as num).toInt(),
        messages: (j['messages'] as List<dynamic>)
            .map((e) =>
                PrivateChatMessageDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: j['has_more'] as bool? ?? false,
        firstUnreadRoomSeq: j['first_unread_room_seq'] != null
            ? (j['first_unread_room_seq'] as num).toInt()
            : null,
      );
}

// ---------------------------------------------------------------------------
// Результат создания чата
// ---------------------------------------------------------------------------

class CreatePrivateChatResultDto {
  final String? chatId;
  final String? error;

  bool get isSuccess => chatId != null;

  const CreatePrivateChatResultDto({this.chatId, this.error});

  factory CreatePrivateChatResultDto.fromJson(Map<String, dynamic> j) =>
      CreatePrivateChatResultDto(
        chatId: j['chat_id'] as String?,
        error: j['error'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Результат проверки canCreate
// ---------------------------------------------------------------------------

class CanCreatePrivateChatDto {
  final bool canCreate;
  final String reason;

  const CanCreatePrivateChatDto({
    required this.canCreate,
    required this.reason,
  });

  factory CanCreatePrivateChatDto.fromJson(Map<String, dynamic> j) =>
      CanCreatePrivateChatDto(
        canCreate: j['can_create'] as bool,
        reason: j['reason'] as String,
      );
}

// ---------------------------------------------------------------------------
// DTO отправленного сообщения
// ---------------------------------------------------------------------------

class SentPrivateChatMessageDto {
  final String id;
  final int roomSeq;
  final DateTime createdAt;
  final String messageKind;
  final bool alreadyExisted;
  final String? error;

  bool get isSuccess => error == null;

  const SentPrivateChatMessageDto({
    required this.id,
    required this.roomSeq,
    required this.createdAt,
    required this.messageKind,
    required this.alreadyExisted,
    this.error,
  });

  factory SentPrivateChatMessageDto.fromJson(Map<String, dynamic> j) {
    if (j['error'] != null) {
      return SentPrivateChatMessageDto(
        id: '',
        roomSeq: 0,
        createdAt: DateTime.now(),
        messageKind: 'USER_TEXT',
        alreadyExisted: false,
        error: j['error'] as String,
      );
    }
    return SentPrivateChatMessageDto(
      id: j['id'] as String,
      roomSeq: (j['room_seq'] as num).toInt(),
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.now(),
      messageKind: j['message_kind'] as String? ?? 'USER_TEXT',
      alreadyExisted: j['already_existed'] as bool? ?? false,
    );
  }
}
