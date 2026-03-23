import 'package:supabase_flutter/supabase_flutter.dart';

import 'block_dto.dart';
import 'blocks_repository.dart';

class BlocksRepositoryImpl implements BlocksRepository {
  final SupabaseClient _client;

  BlocksRepositoryImpl(this._client);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw Exception('Expected map response, got: $value');
  }

  @override
  Future<BlockUserResultDto> blockUser({
    required String appUserId,
    required String targetUserId,
  }) async {
    final response = await _client.rpc(
      'block_user_v1',
      params: {'p_user_id': appUserId, 'p_target_id': targetUserId},
    );
    return BlockUserResultDto.fromJson(_asMap(response));
  }

  @override
  Future<List<BlockedUserDto>> getMyBlocks({required String appUserId}) async {
    final response = await _client.rpc(
      'get_my_blocks_v1',
      params: {'p_user_id': appUserId},
    );
    if (response is List) {
      return response
          .map((e) => BlockedUserDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }
}
