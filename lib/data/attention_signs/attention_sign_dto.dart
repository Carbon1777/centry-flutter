// ---------------------------------------------------------------------------
// Входящий знак (на рассмотрении)
// ---------------------------------------------------------------------------

class IncomingAttentionSignDto {
  final String submissionId;
  final String fromUserId;
  final String? fromNickname;
  final String? fromAvatarUrl;
  final String signTypeId;
  final String stickerUrl;
  final DateTime createdAt;
  final DateTime expiresAt;

  const IncomingAttentionSignDto({
    required this.submissionId,
    required this.fromUserId,
    this.fromNickname,
    this.fromAvatarUrl,
    required this.signTypeId,
    required this.stickerUrl,
    required this.createdAt,
    required this.expiresAt,
  });

  factory IncomingAttentionSignDto.fromJson(Map<String, dynamic> j) =>
      IncomingAttentionSignDto(
        submissionId: j['submission_id'] as String,
        fromUserId: j['from_user_id'] as String,
        fromNickname: j['from_nickname'] as String?,
        fromAvatarUrl: j['from_avatar_url'] as String?,
        signTypeId: j['sign_type_id'] as String,
        stickerUrl: j['sticker_url'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Накопленный знак (в коллекции)
// ---------------------------------------------------------------------------

class CollectedAttentionSignDto {
  final String signTypeId;
  final String stickerUrl;
  final int count;

  const CollectedAttentionSignDto({
    required this.signTypeId,
    required this.stickerUrl,
    required this.count,
  });

  factory CollectedAttentionSignDto.fromJson(Map<String, dynamic> j) =>
      CollectedAttentionSignDto(
        signTypeId: j['sign_type_id'] as String,
        stickerUrl: j['sticker_url'] as String,
        count: (j['count'] as num).toInt(),
      );
}

// ---------------------------------------------------------------------------
// Мой текущий знак (можно отправить)
// ---------------------------------------------------------------------------

class MyDailyAttentionSignDto {
  final String dailySignId;
  final String signTypeId;
  final String stickerUrl;
  final DateTime allocatedDate;
  final DateTime expiresAt;

  const MyDailyAttentionSignDto({
    required this.dailySignId,
    required this.signTypeId,
    required this.stickerUrl,
    required this.allocatedDate,
    required this.expiresAt,
  });

  factory MyDailyAttentionSignDto.fromJson(Map<String, dynamic> j) =>
      MyDailyAttentionSignDto(
        dailySignId: j['daily_sign_id'] as String,
        signTypeId: j['sign_type_id'] as String,
        stickerUrl: j['sticker_url'] as String,
        allocatedDate: DateTime.parse(j['allocated_date'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Коробка (все 3 блока)
// ---------------------------------------------------------------------------

class AttentionSignBoxDto {
  final MyDailyAttentionSignDto? mySign;
  final List<IncomingAttentionSignDto> incoming;
  final List<CollectedAttentionSignDto> collection;

  const AttentionSignBoxDto({
    this.mySign,
    required this.incoming,
    required this.collection,
  });

  factory AttentionSignBoxDto.fromJson(Map<String, dynamic> j) =>
      AttentionSignBoxDto(
        mySign: j['my_sign'] != null
            ? MyDailyAttentionSignDto.fromJson(
                j['my_sign'] as Map<String, dynamic>)
            : null,
        incoming: (j['incoming'] as List<dynamic>)
            .map((e) => IncomingAttentionSignDto.fromJson(
                e as Map<String, dynamic>))
            .toList(),
        collection: (j['collection'] as List<dynamic>)
            .map((e) => CollectedAttentionSignDto.fromJson(
                e as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Результат отправки знака
// ---------------------------------------------------------------------------

class SendAttentionSignResultDto {
  final String? submissionId;
  final bool ok;
  final String? error;

  bool get isSuccess => ok && error == null;

  const SendAttentionSignResultDto({
    this.submissionId,
    required this.ok,
    this.error,
  });

  factory SendAttentionSignResultDto.fromJson(Map<String, dynamic> j) =>
      SendAttentionSignResultDto(
        submissionId: j['submission_id'] as String?,
        ok: j['ok'] as bool? ?? false,
        error: j['error'] as String?,
      );
}
