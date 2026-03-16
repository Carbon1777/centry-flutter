import 'bonus_summary_dto.dart';
import 'bonus_ledger_entry_dto.dart';

abstract class BonusRepository {
  /// Текущий баланс и суммарное начисление пользователя.
  Future<BonusSummaryDto> getSummary({required String appUserId});

  /// Постраничная история начислений (новые сверху).
  Future<List<BonusLedgerEntryDto>> getHistory({
    required String appUserId,
    int limit = 20,
    int offset = 0,
  });
}
