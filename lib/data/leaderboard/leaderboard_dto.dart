// DTO для рейтинга — данные как есть с сервера, без бизнес-логики на клиенте

class LeaderboardEntryDto {
  final String appUserId;
  final String nickname;
  final String? avatarUrl;
  final String? city;
  final int place;
  final int score;

  const LeaderboardEntryDto({
    required this.appUserId,
    required this.nickname,
    this.avatarUrl,
    this.city,
    required this.place,
    required this.score,
  });

  factory LeaderboardEntryDto.fromMap(Map<String, dynamic> m) {
    return LeaderboardEntryDto(
      appUserId: m['app_user_id'] as String,
      nickname: (m['nickname'] as String?) ?? '',
      avatarUrl: m['avatar_url'] as String?,
      city: m['city'] as String?,
      place: (m['place'] as num).toInt(),
      score: (m['score'] as num).toInt(),
    );
  }
}

class LeaderboardColumnDto {
  final List<LeaderboardEntryDto> top10;
  final LeaderboardEntryDto? myEntry; // null если caller в top10 или нет данных

  const LeaderboardColumnDto({
    required this.top10,
    this.myEntry,
  });

  factory LeaderboardColumnDto.fromMap(Map<String, dynamic> m) {
    final rawTop10 = m['top10'] as List<dynamic>? ?? [];
    return LeaderboardColumnDto(
      top10: rawTop10
          .map((e) => LeaderboardEntryDto.fromMap(e as Map<String, dynamic>))
          .toList(),
      myEntry: m['my_entry'] != null
          ? LeaderboardEntryDto.fromMap(
              m['my_entry'] as Map<String, dynamic>)
          : null,
    );
  }
}

class LeaderboardSnapshotDto {
  final LeaderboardColumnDto tokens;
  final LeaderboardColumnDto activity;

  const LeaderboardSnapshotDto({
    required this.tokens,
    required this.activity,
  });

  factory LeaderboardSnapshotDto.fromMap(Map<String, dynamic> m) {
    return LeaderboardSnapshotDto(
      tokens: LeaderboardColumnDto.fromMap(
          m['tokens'] as Map<String, dynamic>),
      activity: LeaderboardColumnDto.fromMap(
          m['activity'] as Map<String, dynamic>),
    );
  }
}

class SympathyLeaderboardSnapshotDto {
  final LeaderboardColumnDto received;
  final LeaderboardColumnDto sent;

  const SympathyLeaderboardSnapshotDto({
    required this.received,
    required this.sent,
  });

  factory SympathyLeaderboardSnapshotDto.fromMap(Map<String, dynamic> m) {
    return SympathyLeaderboardSnapshotDto(
      received: LeaderboardColumnDto.fromMap(
          m['received'] as Map<String, dynamic>),
      sent: LeaderboardColumnDto.fromMap(
          m['sent'] as Map<String, dynamic>),
    );
  }
}
