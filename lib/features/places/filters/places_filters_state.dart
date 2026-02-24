class PlacesFiltersState {
  final List<String> cityIds;
  final List<String> areaIds;
  final List<String> types;

  const PlacesFiltersState({
    required this.cityIds,
    required this.areaIds,
    required this.types,
  });

  factory PlacesFiltersState.empty() {
    return const PlacesFiltersState(
      cityIds: [],
      areaIds: [],
      types: [],
    );
  }

  PlacesFiltersState copyWith({
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
  }) {
    return PlacesFiltersState(
      cityIds: cityIds ?? this.cityIds,
      areaIds: areaIds ?? this.areaIds,
      types: types ?? this.types,
    );
  }
}
