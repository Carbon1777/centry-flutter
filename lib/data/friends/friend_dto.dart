class FriendDto {
  final String friendUserId;
  final String displayName;
  final String publicId;
  final String note;

  const FriendDto({
    required this.friendUserId,
    required this.displayName,
    required this.publicId,
    required this.note,
  });

  static FriendDto fromJson(Map<String, dynamic> json) {
    return FriendDto(
      friendUserId: (json['friend_user_id'] as String?) ?? '',
      displayName: (json['friend_display_name'] as String?) ?? '',
      publicId: (json['friend_public_id'] as String?) ?? '',
      note: (json['note'] as String?) ?? '',
    );
  }
}
