import 'package:supabase_flutter/supabase_flutter.dart';

import 'bonus_ledger_entry_dto.dart';
import 'bonus_repository.dart';
import 'bonus_summary_dto.dart';

class BonusRepositoryImpl implements BonusRepository {
  final SupabaseClient _client;

  BonusRepositoryImpl(this._client);

  @override
  Future<BonusSummaryDto> getSummary({required String appUserId}) async {
    final response = await _client.rpc(
      'get_my_bonus_summary_v1',
      params: {'p_app_user_id': appUserId},
    );
    return BonusSummaryDto.fromJson(response as Map<String, dynamic>);
  }

  @override
  Future<List<BonusLedgerEntryDto>> getHistory({
    required String appUserId,
    int limit = 20,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      'get_my_bonus_history_v1',
      params: {
        'p_app_user_id': appUserId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final items = (response as List<dynamic>? ?? []);
    return items
        .map((e) => BonusLedgerEntryDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
