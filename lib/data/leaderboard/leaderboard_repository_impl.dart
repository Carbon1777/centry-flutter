import 'package:supabase_flutter/supabase_flutter.dart';

import 'leaderboard_dto.dart';
import 'leaderboard_repository.dart';

class LeaderboardRepositoryImpl implements LeaderboardRepository {
  final SupabaseClient _client;

  const LeaderboardRepositoryImpl(this._client);

  @override
  Future<LeaderboardSnapshotDto> getSnapshot({required String appUserId}) async {
    final res = await _client.rpc(
      'get_leaderboard_snapshot_v1',
      params: {'p_app_user_id': appUserId},
    );
    if (res == null) throw StateError('get_leaderboard_snapshot_v1 returned null');
    return LeaderboardSnapshotDto.fromMap(
      (res as Map).cast<String, dynamic>(),
    );
  }
}
