import 'leaderboard_dto.dart';

abstract class LeaderboardRepository {
  Future<LeaderboardSnapshotDto> getSnapshot({required String appUserId});
  Future<SympathyLeaderboardSnapshotDto> getSympathySnapshot({required String appUserId});
}
