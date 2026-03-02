class AcceptFriendResultDto {
  final String status; // ACCEPTED
  final String friendUserId;
  final String friendDisplayName;
  final String friendPublicId;

  const AcceptFriendResultDto({
    required this.status,
    required this.friendUserId,
    required this.friendDisplayName,
    required this.friendPublicId,
  });

  static AcceptFriendResultDto fromJson(Map<String, dynamic> json) {
    // В БД-функции используется result_status (чтобы избежать проблем с редактором).
    final status =
        (json['result_status'] as String?) ?? (json['status'] as String?) ?? '';
    return AcceptFriendResultDto(
      status: status,
      friendUserId: (json['friend_user_id'] as String?) ?? '',
      friendDisplayName: (json['friend_display_name'] as String?) ?? '',
      friendPublicId: (json['friend_public_id'] as String?) ?? '',
    );
  }
}
