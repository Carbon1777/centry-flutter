class LegalAcceptanceStatusDto {
  final bool needsAcceptance;
  final String? currentTerms;
  final String? currentPrivacy;
  final String? currentBonusRules;
  final String? currentChildSafety;

  const LegalAcceptanceStatusDto({
    required this.needsAcceptance,
    this.currentTerms,
    this.currentPrivacy,
    this.currentBonusRules,
    this.currentChildSafety,
  });

  factory LegalAcceptanceStatusDto.fromJson(Map<String, dynamic> json) {
    return LegalAcceptanceStatusDto(
      needsAcceptance:    json['needs_acceptance'] as bool,
      currentTerms:       json['current_terms'] as String?,
      currentPrivacy:     json['current_privacy'] as String?,
      currentBonusRules:  json['current_bonus_rules'] as String?,
      currentChildSafety: json['current_child_safety'] as String?,
    );
  }
}
