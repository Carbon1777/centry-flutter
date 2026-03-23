class ModalEventDto {
  final String eventId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? actorNickname;
  final String? actorAvatarUrl;
  final String? stickerUrl;

  const ModalEventDto({
    required this.eventId,
    required this.eventType,
    required this.payload,
    required this.createdAt,
    this.actorNickname,
    this.actorAvatarUrl,
    this.stickerUrl,
  });

  factory ModalEventDto.fromJson(Map<String, dynamic> j) => ModalEventDto(
        eventId: j['event_id'] as String,
        eventType: j['event_type'] as String,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: DateTime.parse(j['created_at'] as String),
        actorNickname: j['actor_nickname'] as String?,
        actorAvatarUrl: j['actor_avatar_url'] as String?,
        stickerUrl: j['sticker_url'] as String?,
      );
}
