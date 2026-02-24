class PlanSummaryDto {
  final String id;
  final String title;
  final String? description;

  final String role;
  final String status;

  final DateTime? votingDeadlineAt;
  final DateTime? eventAt;

  final String? decidedPlaceId;
  final DateTime? decidedDateAt;

  final DateTime? tieResolutionDeadlineAt;

  final bool visibleInFeed;
  final bool archived;

  final int membersCount;
  final int placesCount;
  final int datesCount;

  final String? myPlaceVote;
  final DateTime? myDateVote;

  final DateTime createdAt;
  final DateTime updatedAt;

  PlanSummaryDto({
    required this.id,
    required this.title,
    required this.description,
    required this.role,
    required this.status,
    required this.votingDeadlineAt,
    required this.eventAt,
    required this.decidedPlaceId,
    required this.decidedDateAt,
    required this.tieResolutionDeadlineAt,
    required this.visibleInFeed,
    required this.archived,
    required this.membersCount,
    required this.placesCount,
    required this.datesCount,
    required this.myPlaceVote,
    required this.myDateVote,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime? _asDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  factory PlanSummaryDto.fromJson(Map<String, dynamic> json) {
    return PlanSummaryDto(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description']?.toString(),
      role: json['role'] as String,
      status: json['status'] as String,
      votingDeadlineAt: _asDate(json['voting_deadline_at']),
      eventAt: _asDate(json['event_at']),
      decidedPlaceId: json['decided_place_id']?.toString(),
      decidedDateAt: _asDate(json['decided_date_at']),
      tieResolutionDeadlineAt: _asDate(json['tie_resolution_deadline_at']),
      visibleInFeed: (json['visible_in_feed'] as bool?) ?? false,
      archived: (json['archived'] as bool?) ?? false,
      membersCount: _asInt(json['members_count']),
      placesCount: _asInt(json['places_count']),
      datesCount: _asInt(json['dates_count']),
      myPlaceVote: json['my_place_vote']?.toString(),
      myDateVote: _asDate(json['my_date_vote']),
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}
