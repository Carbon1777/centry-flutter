import 'block_dto.dart';

abstract class BlocksRepository {
  Future<BlockUserResultDto> blockUser({
    required String appUserId,
    required String targetUserId,
  });

  Future<List<BlockedUserDto>> getMyBlocks({required String appUserId});
}
