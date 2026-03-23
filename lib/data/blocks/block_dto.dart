class BlockedUserDto {
  final String blockId;
  final String blockedUserId;
  final DateTime blockedAt;
  final String? nickname;
  final String? avatarUrl;

  const BlockedUserDto({
    required this.blockId,
    required this.blockedUserId,
    required this.blockedAt,
    this.nickname,
    this.avatarUrl,
  });

  factory BlockedUserDto.fromJson(Map<String, dynamic> j) => BlockedUserDto(
        blockId: j['block_id'] as String,
        blockedUserId: j['blocked_user_id'] as String,
        blockedAt: DateTime.parse(j['blocked_at'] as String),
        nickname: j['nickname'] as String?,
        avatarUrl: j['avatar_url'] as String?,
      );
}

class BlockUserResultDto {
  final bool ok;
  final bool hadChat;
  final String? error;

  bool get isSuccess => ok && error == null;

  const BlockUserResultDto({required this.ok, required this.hadChat, this.error});

  factory BlockUserResultDto.fromJson(Map<String, dynamic> j) => BlockUserResultDto(
        ok: j['ok'] as bool? ?? false,
        hadChat: j['had_chat'] as bool? ?? false,
        error: j['error'] as String?,
      );
}
