class LegalAcceptanceStatusDto {
  final bool needsAcceptance;
  final String? currentTerms;
  final String? currentPrivacy;
  final String? currentBonusRules;

  const LegalAcceptanceStatusDto({
    required this.needsAcceptance,
    this.currentTerms,
    this.currentPrivacy,
    this.currentBonusRules,
  });

  factory LegalAcceptanceStatusDto.fromJson(Map<String, dynamic> json) {
    return LegalAcceptanceStatusDto(
      needsAcceptance:  json['needs_acceptance'] as bool,
      currentTerms:     json['current_terms'] as String?,
      currentPrivacy:   json['current_privacy'] as String?,
      currentBonusRules: json['current_bonus_rules'] as String?,
    );
  }
}
