import 'package:supabase_flutter/supabase_flutter.dart';

import 'feed_place_dto.dart';
import 'feed_repository.dart';
import 'plan_shell_dto.dart';

class FeedRepositoryImpl implements FeedRepository {
  final SupabaseClient _client;

  FeedRepositoryImpl(this._client);

  @override
  Future<List<FeedPlaceDto>> getFeedNearby({
    double? lat,
    double? lng,
    int limit = 25,
  }) async {
    final raw = await _client.rpc('get_feed_nearby', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_limit': limit,
    });

    if (raw == null) return [];

    final List<dynamic> list;
    if (raw is List) {
      list = raw;
    } else if (raw is String) {
      // Supabase может вернуть строку-JSON
      throw StateError('get_feed_nearby: unexpected String response');
    } else {
      list = [];
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(FeedPlaceDto.fromJson)
        .toList();
  }

  @override
  Future<List<PlanShellDto>> getPlanShells(String placeId) async {
    final raw = await _client.rpc('get_place_plan_shells', params: {
      'p_place_id': placeId,
    });

    if (raw == null) return [];

    final List<dynamic> list;
    if (raw is List) {
      list = raw;
    } else {
      list = [];
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(PlanShellDto.fromJson)
        .toList();
  }
}
