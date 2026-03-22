import 'dart:async';

import 'place_dto.dart';
import 'places_feed_result.dart';

abstract class PlacesRepository {
  /// Live invalidation stream.
  ///
  /// Emits after successful server-side mutation (e.g. vote, toggle saved).
  /// Consumers (list/map) must refetch canonical data.
  Stream<void> get invalidations;

  /// Canonical server-driven feed.
  ///
  /// Contract:
  /// - Client is dumb.
  /// - Server is the source of truth for DEFAULT/GEO mode and ordering.
  /// - If GeoService has a position, repo calls the server in GEO mode.
  /// - If no geo, repo calls the server in DEFAULT mode.
  /// - Filters are only constraints; ordering is always server-side.
  ///
  /// Search contract:
  /// - searchTitle is an optional exact-title constraint (user picked a suggestion and pressed "Find").
  /// - Server returns only places with matching title (then normal GEO/DEFAULT ordering rules apply).
  Future<PlacesFeedResult> loadPlacesFeed({
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
    double? minRating,
    String? searchTitle,
    required int limit,
    required int offset,
  });

  /// Autocomplete suggestions for places search.
  Future<List<String>> loadPlaceSearchSuggestions({
    required String query,
    int limit = 7,
  });

  /// Legacy compatibility
  Future<PlacesFeedResult> loadPlaces({
    required int limit,
    required int offset,
  });

  Future<PlacesFeedResult> loadPlacesWithFilters({
    required String cityId,
    List<String>? areaIds,
    List<String>? types,
    required int limit,
    required int offset,
  });

  Future<PlacesFeedResult> loadPlacesMultiCity({
    required List<String> cityIds,
    List<String>? areaIds,
    List<String>? types,
    required int limit,
    required int offset,
  });

  Future<List<PlaceDto>> loadPlacesMap({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
    double? minRating,
  });

  /// Approximate geographic center for the given location filter.
  /// If [areaIds] is non-empty, centers on areas (more specific).
  /// Otherwise centers on [cityIds].
  /// Returns null if no places found.
  Future<Map<String, double>?> getCenterForFilter({
    List<String>? cityIds,
    List<String>? areaIds,
  });

  Future<Map<String, dynamic>> loadPlacesFiltersState({
    double? lat,
    double? lng,
    List<String>? selectedCityIds,
    List<String>? selectedAreaIds,
    List<String>? selectedTypes,
    double? minRating,
  });

  /// Meta/content snapshot for place (without social part).
  Future<Map<String, dynamic>> getPlaceDetailsMeta({
    required String placeId,
  });

  Future<Map<String, dynamic>> getPlaceDetails({
    required String placeId,
  });

  Future<Map<String, dynamic>> votePlace({
    required String placeId,
    required int value,
  });

  /// 🔹 Toggle saved state (My Places)
  ///
  /// Server is source of truth.
  /// After successful mutation, repository must emit invalidation.
  Future<void> toggleSavedPlace(String placeId);

  /// 🔹 My Places — canonical server snapshot
  ///
  /// Returns only places marked by current domain user.
  /// Server is source of truth.
  Future<List<PlaceDto>> getMyPlaces();

  /// 🔹 Create user place submission (ordinary flow)
  ///
  /// Canonical server RPC:
  /// create_place_submission_v1(...)
  Future<Map<String, dynamic>> createPlaceSubmission({
    required String title,
    required String category,
    required String city,
    required String street,
    required String house,
    String? website,
  });

  /// 🔹 Create user place submission and immediately try to add it into plan
  ///
  /// Canonical server RPC:
  /// create_place_submission_and_add_to_plan_v1(...)
  Future<Map<String, dynamic>> createPlaceSubmissionAndAddToPlan({
    required String planId,
    required String title,
    required String category,
    required String city,
    required String street,
    required String house,
    String? website,
  });
}
