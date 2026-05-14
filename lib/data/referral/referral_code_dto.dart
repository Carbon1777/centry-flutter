/// Ответ RPC `get_or_create_my_referral_code_v1`. См. TZ_referral_program.md §4.4.
class ReferralCodeDto {
  final String code;
  final String shareUrl;
  final String deepLink;
  final String shareText;

  const ReferralCodeDto({
    required this.code,
    required this.shareUrl,
    required this.deepLink,
    required this.shareText,
  });

  factory ReferralCodeDto.fromJson(Map<String, dynamic> json) {
    return ReferralCodeDto(
      code: (json['code'] as String?) ?? '',
      shareUrl: (json['share_url'] as String?) ?? '',
      deepLink: (json['deep_link'] as String?) ?? '',
      shareText: (json['share_text'] as String?) ?? '',
    );
  }
}
