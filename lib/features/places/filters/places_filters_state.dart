// Общие UI-модели для фильтров мест.
// PlaceFilterItem и PlaceRatingOption вынесены сюда, чтобы
// контроллер и диалог могли их использовать без циклического импорта.

class PlaceFilterItem {
  final String id;
  final String title;

  const PlaceFilterItem({required this.id, required this.title});
}

class PlaceRatingOption {
  final double value;
  final String label;

  const PlaceRatingOption({required this.value, required this.label});
}

class PlacesFiltersState {
  final List<String> cityIds;
  final List<String> areaIds;
  final List<String> types;
  final double? minRating;

  const PlacesFiltersState({
    required this.cityIds,
    required this.areaIds,
    required this.types,
    this.minRating,
  });

  factory PlacesFiltersState.empty() {
    return const PlacesFiltersState(
      cityIds: [],
      areaIds: [],
      types: [],
      minRating: null,
    );
  }

  bool get hasActiveFilters =>
      cityIds.isNotEmpty ||
      areaIds.isNotEmpty ||
      types.isNotEmpty ||
      minRating != null;

  PlacesFiltersState copyWith({
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
    // Используем sentinel чтобы различать "не передали" и "передали null"
    Object? minRating = _kSentinel,
  }) {
    return PlacesFiltersState(
      cityIds: cityIds ?? this.cityIds,
      areaIds: areaIds ?? this.areaIds,
      types: types ?? this.types,
      minRating: minRating == _kSentinel
          ? this.minRating
          : minRating as double?,
    );
  }
}

const _kSentinel = Object();
