class FeedPlaceDto {
  final String placeId;
  final String name;
  final String category;
  final String? photoStorageKey;
  final int? distanceMeters;
  final String? metroName;
  final int? metroDistanceMeters;
  final double? rating;
  final int countPlans;
  final int interestedCount;
  final int plannedCount;
  final int visitedCount;
  final int pastPlansCount;
  final double? lat;
  final double? lng;

  const FeedPlaceDto({
    required this.placeId,
    required this.name,
    required this.category,
    required this.photoStorageKey,
    required this.distanceMeters,
    required this.metroName,
    required this.metroDistanceMeters,
    required this.rating,
    required this.countPlans,
    required this.interestedCount,
    required this.plannedCount,
    required this.visitedCount,
    required this.pastPlansCount,
    this.lat,
    this.lng,
  });

  static int? _asIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  factory FeedPlaceDto.fromJson(Map<String, dynamic> json) {
    return FeedPlaceDto(
      placeId: json['place_id'] as String,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      photoStorageKey: json['photo_url'] as String?,
      distanceMeters: _asIntNullable(json['distance_meters']),
      metroName: json['metro_name'] as String?,
      metroDistanceMeters: _asIntNullable(json['metro_distance_meters']),
      rating: _asDouble(json['rating']),
      countPlans: (json['count_plans'] as num?)?.toInt() ?? 0,
      interestedCount: (json['interested_count'] as num?)?.toInt() ?? 0,
      plannedCount: (json['planned_count'] as num?)?.toInt() ?? 0,
      visitedCount: (json['visited_count'] as num?)?.toInt() ?? 0,
      pastPlansCount: (json['past_plans_count'] as num?)?.toInt() ?? 0,
      lat: _asDouble(json['lat']),
      lng: _asDouble(json['lng']),
    );
  }
}
