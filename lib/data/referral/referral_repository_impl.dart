import 'package:supabase_flutter/supabase_flutter.dart';

import 'referral_code_dto.dart';
import 'referral_repository.dart';

class ReferralRepositoryImpl implements ReferralRepository {
  final SupabaseClient _client;

  ReferralRepositoryImpl(this._client);

  @override
  Future<ReferralCodeDto> getOrCreateMyCode() async {
    final response = await _client.rpc('get_or_create_my_referral_code_v1');
    return ReferralCodeDto.fromJson(response as Map<String, dynamic>);
  }
}
