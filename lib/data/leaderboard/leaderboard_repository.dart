import 'leaderboard_dto.dart';

abstract class LeaderboardRepository {
  Future<LeaderboardSnapshotDto> getSnapshot({required String appUserId});
}
