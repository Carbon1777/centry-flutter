class PlacesFiltersPayload {
  final List<String>? cityIds;
  final List<String>? areaIds;
  final List<String>? types;
  final double? minRating;

  const PlacesFiltersPayload({
    this.cityIds,
    this.areaIds,
    this.types,
    this.minRating,
  });

  Map<String, dynamic> toJson() {
    return {
      'city_ids': cityIds,
      'area_ids': areaIds,
      'types': types,
      'min_rating': minRating,
    };
  }
}
