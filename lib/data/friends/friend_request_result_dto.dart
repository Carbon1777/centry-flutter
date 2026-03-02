class FriendRequestResultDto {
  final String? requestId;
  final String requestStatus; // PENDING | ALREADY_FRIENDS
  final String requestDirection; // OUTGOING | INCOMING | NONE
  final String targetUserId;
  final String targetDisplayName;
  final String targetPublicId;

  const FriendRequestResultDto({
    required this.requestId,
    required this.requestStatus,
    required this.requestDirection,
    required this.targetUserId,
    required this.targetDisplayName,
    required this.targetPublicId,
  });

  static FriendRequestResultDto fromJson(Map<String, dynamic> json) {
    return FriendRequestResultDto(
      requestId: json['request_id'] as String?,
      requestStatus: (json['request_status'] as String?) ?? '',
      requestDirection: (json['request_direction'] as String?) ?? '',
      targetUserId: (json['target_user_id'] as String?) ?? '',
      targetDisplayName: (json['target_display_name'] as String?) ?? '',
      targetPublicId: (json['target_public_id'] as String?) ?? '',
    );
  }
}
