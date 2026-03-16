class ParticipantPreviewDto {
  final String kind; // "public" | "anon"
  final String? userId; // app_user_id — только для public
  final String? nickname;
  final bool nicknameHidden;
  final String? avatarUrl;
  final bool avatarHidden;
  final String? publicId;

  const ParticipantPreviewDto({
    required this.kind,
    this.userId,
    this.nickname,
    this.nicknameHidden = false,
    this.avatarUrl,
    this.avatarHidden = false,
    this.publicId,
  });

  bool get isPublic => kind == 'public';

  factory ParticipantPreviewDto.fromJson(Map<String, dynamic> json) {
    return ParticipantPreviewDto(
      kind: json['kind'] as String? ?? 'anon',
      userId: json['user_id'] as String?,
      nickname: json['nickname'] as String?,
      nicknameHidden: json['nickname_hidden'] as bool? ?? false,
      avatarUrl: json['avatar_url'] as String?,
      avatarHidden: json['avatar_hidden'] as bool? ?? false,
      publicId: json['public_id'] as String?,
    );
  }
}
