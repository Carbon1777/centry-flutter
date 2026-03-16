class BonusLedgerEntryDto {
  final String id;
  final int amount;
  final String entryType;
  final String rewardCode;
  final String title;
  final String description;
  final String? sourceEntityType;
  final String? sourceEntityId;
  final DateTime createdAt;

  const BonusLedgerEntryDto({
    required this.id,
    required this.amount,
    required this.entryType,
    required this.rewardCode,
    required this.title,
    required this.description,
    this.sourceEntityType,
    this.sourceEntityId,
    required this.createdAt,
  });

  factory BonusLedgerEntryDto.fromJson(Map<String, dynamic> json) {
    return BonusLedgerEntryDto(
      id: (json['id'] as String?) ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      entryType: (json['entry_type'] as String?) ?? 'credit',
      rewardCode: (json['reward_code'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      sourceEntityType: json['source_entity_type'] as String?,
      sourceEntityId: json['source_entity_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}
