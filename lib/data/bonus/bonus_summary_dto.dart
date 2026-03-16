class BonusSummaryDto {
  final int currentBalance;
  final int totalEarned;

  const BonusSummaryDto({
    required this.currentBalance,
    required this.totalEarned,
  });

  factory BonusSummaryDto.fromJson(Map<String, dynamic> json) {
    return BonusSummaryDto(
      currentBalance: (json['current_balance'] as num?)?.toInt() ?? 0,
      totalEarned: (json['total_earned'] as num?)?.toInt() ?? 0,
    );
  }
}
