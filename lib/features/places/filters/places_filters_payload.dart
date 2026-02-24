class PlacesFiltersPayload {
  final List<String>? cityIds;
  final List<String>? areaIds;
  final List<String>? types;

  const PlacesFiltersPayload({
    this.cityIds,
    this.areaIds,
    this.types,
  });

  Map<String, dynamic> toJson() {
    return {
      'city_ids': cityIds,
      'area_ids': areaIds,
      'types': types,
    };
  }
}
