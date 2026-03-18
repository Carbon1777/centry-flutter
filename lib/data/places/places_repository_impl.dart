import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/geo/geo_service.dart';
import '../local/user_snapshot_storage.dart';
import 'place_dto.dart';
import 'places_feed_result.dart';
import 'places_repository.dart';

class PlacesRepositoryImpl implements PlacesRepository {
  final SupabaseClient _client;

  // 🔴 LIVE INVALIDATION STREAM
  final StreamController<void> _invalidationController =
      StreamController<void>.broadcast();

  @override
  Stream<void> get invalidations => _invalidationController.stream;

  PlacesRepositoryImpl(this._client);

  // ===========================================================
  // INTERNAL: DOMAIN USER RESOLVE
  // ===========================================================

  Future<Map<String, dynamic>?> _fetchDomainUserByAuthUserId(
    String authUserId,
  ) async {
    // Важно: param-name у функции на сервере может отличаться.
    // Поэтому пробуем несколько вариантов строго последовательно.
    final candidates = <Map<String, dynamic>>[
      {'p_auth_user_id': authUserId},
      {'auth_user_id': authUserId},
      {'p_user_id': authUserId},
      {'user_id': authUserId},
      {'p_id': authUserId},
      {'id': authUserId},
      {'input': authUserId},
    ];

    for (final params in candidates) {
      try {
        final raw = await _client.rpc(
          'get_domain_user_by_auth_user_id',
          params: params,
        );

        if (raw == null) return null;

        // Вариант A: функция возвращает json-объект напрямую
        if (raw is Map) {
          final map = Map<String, dynamic>.from(raw);

          // иногда Supabase оборачивает в ключ с именем функции
          final inner = map['get_domain_user_by_auth_user_id'];
          if (inner is Map) {
            return Map<String, dynamic>.from(inner);
          }

          if (map.containsKey('id')) return map;
        }

        // Вариант B: функция/вызов возвращает list из одной строки
        if (raw is List && raw.isNotEmpty) {
          final first = raw.first;
          if (first is Map) {
            final map = Map<String, dynamic>.from(first);

            final inner = map['get_domain_user_by_auth_user_id'];
            if (inner is Map) {
              return Map<String, dynamic>.from(inner);
            }

            if (map.containsKey('id')) return map;
          }
        }

        // Ничего не распарсили — считаем как "не найдено"
        return null;
      } catch (_) {
        // try next param variant
      }
    }

    return null;
  }

  Future<String> _resolveDomainUserId() async {
    // Always read snapshot first (no blind cache usage)
    final snapshot = await UserSnapshotStorage().read();
    final id = snapshot?.id;

    if (id != null && id.isNotEmpty) {
      return id;
    }

    // Snapshot missing → attempt restore from auth session
    final session = _client.auth.currentSession;
    if (session != null) {
      final authId = session.user.id;

      final row = await _fetchDomainUserByAuthUserId(authId);

      if (row != null) {
        final domainId = (row['id'] ?? '').toString();
        final publicId = (row['public_id'] ?? '').toString();
        final nickname =
            (row['nickname'] ?? row['display_name'] ?? '').toString();
        final state = (row['state'] ?? 'USER').toString();

        if (domainId.isNotEmpty) {
          await UserSnapshotStorage().save(
            UserSnapshot(
              id: domainId,
              publicId: publicId,
              nickname: nickname,
              state: state,
            ),
          );


          return domainId;
        }
      }
    }

    throw StateError('Domain user id not available');
  }

  Map<String, dynamic> _expectJsonMap(String fn, dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }

    throw StateError('Unexpected $fn response');
  }

  // ===========================================================
  // INTERNAL: FEED (v2)
  // ===========================================================

  Future<PlacesFeedResult> _loadPlacesFeedV2({
    double? lat,
    double? lng,
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
    double? minRating,
    String? searchTitle,
    required int limit,
    required int offset,
  }) async {
    final params = <String, dynamic>{
      'p_limit': limit,
      'p_offset': offset,
      if (cityIds != null && cityIds.isNotEmpty) 'p_city_ids': cityIds,
      if (areaIds != null && areaIds.isNotEmpty) 'p_area_ids': areaIds,
      if (types != null && types.isNotEmpty) 'p_types': types,
      if (minRating != null) 'p_min_rating': minRating,
      if (searchTitle != null && searchTitle.isNotEmpty)
        'p_search_title': searchTitle,
      if (lat != null) 'p_lat': lat,
      if (lng != null) 'p_lng': lng,
    };

    final raw = await _client.rpc(
      'get_places_feed_v5',
      params: params,
    );

    Map<String, dynamic> response;

    if (raw is Map) {
      response = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      response = Map<String, dynamic>.from(raw.first as Map);
    } else {
      throw StateError('Unexpected get_places_feed_v4 response');
    }

    final meta = response['meta'] as Map? ?? const {};
    final itemsJson = response['items'] as List? ?? const [];

    final items = itemsJson
        .whereType<Map>()
        .map((e) => PlaceDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return PlacesFeedResult(
      items: items,
      hasMore: meta['has_more'] as bool? ?? false,
    );
  }

  // ===========================================================
  // FEED (CANONICAL)
  // ===========================================================

  @override
  Future<PlacesFeedResult> loadPlacesFeed({
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
    double? minRating,
    String? searchTitle,
    required int limit,
    required int offset,
  }) async {
    final geo = GeoService.instance.current.value;

    return await _loadPlacesFeedV2(
      lat: geo?.lat,
      lng: geo?.lng,
      cityIds: cityIds,
      areaIds: areaIds,
      types: types,
      minRating: minRating,
      searchTitle: searchTitle,
      limit: limit,
      offset: offset,
    );
  }

  // ===========================================================
  // SEARCH SUGGESTIONS
  // ===========================================================

  @override
  Future<List<String>> loadPlaceSearchSuggestions({
    required String query,
    int limit = 7,
  }) async {
    if (query.trim().isEmpty) return [];

    final raw = await _client.rpc(
      'search_places_suggestions_v1',
      params: {
        'p_query': query,
        'p_limit': limit,
      },
    );

    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }

    return [];
  }

  // ===========================================================
  // Legacy wrappers
  // ===========================================================

  @override
  Future<PlacesFeedResult> loadPlaces({
    required int limit,
    required int offset,
  }) {
    return loadPlacesFeed(
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<PlacesFeedResult> loadPlacesWithFilters({
    required String cityId,
    List<String>? areaIds,
    List<String>? types,
    required int limit,
    required int offset,
  }) {
    return loadPlacesFeed(
      cityIds: [cityId],
      areaIds: areaIds,
      types: types,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<PlacesFeedResult> loadPlacesMultiCity({
    required List<String> cityIds,
    List<String>? areaIds,
    List<String>? types,
    required int limit,
    required int offset,
  }) {
    return loadPlacesFeed(
      cityIds: cityIds,
      areaIds: areaIds,
      types: types,
      limit: limit,
      offset: offset,
    );
  }

  // ===========================================================
  // FILTER STATE
  // ===========================================================

  @override
  Future<Map<String, dynamic>> loadPlacesFiltersState({
    double? lat,
    double? lng,
    List<String>? selectedCityIds,
    List<String>? selectedAreaIds,
    List<String>? selectedTypes,
    double? minRating,
  }) async {
    final params = {
      if (lat != null) 'p_lat': lat,
      if (lng != null) 'p_lng': lng,
      // Отправляем всегда когда не null:
      // [] = явно «никакой» (все районы, без автогео)
      // [id] = конкретные города
      if (selectedCityIds != null)
        'p_selected_city_ids': selectedCityIds,
      if (selectedAreaIds != null && selectedAreaIds.isNotEmpty)
        'p_selected_area_ids': selectedAreaIds,
      if (selectedTypes != null && selectedTypes.isNotEmpty)
        'p_selected_types': selectedTypes,
      if (minRating != null) 'p_min_rating': minRating,
    };

    final response = await _client.rpc(
      'get_places_filters_v2',
      params: params,
    );

    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }

    throw StateError('Unexpected filters RPC response');
  }

  // ===========================================================
  // MAP
  // ===========================================================

  @override
  Future<List<PlaceDto>> loadPlacesMap({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    List<String>? cityIds,
    List<String>? areaIds,
    List<String>? types,
  }) async {
    try {
      final params = {
        'p_min_lat': minLat,
        'p_min_lng': minLng,
        'p_max_lat': maxLat,
        'p_max_lng': maxLng,
        if (cityIds != null && cityIds.isNotEmpty) 'p_city_ids': cityIds,
        if (areaIds != null && areaIds.isNotEmpty) 'p_area_ids': areaIds,
        if (types != null && types.isNotEmpty) 'p_types': types,
      };

      final response = await _client.rpc(
        'get_places_map_v2',
        params: params,
      );

      if (response is! List) {
        throw StateError('Unexpected get_places_map_v2 response');
      }

      return response
          .whereType<Map>()
          .map((e) => PlaceDto.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================
  // DETAILS
  // ===========================================================

  @override
  Future<Map<String, dynamic>> getPlaceDetails({
    required String placeId,
  }) async {
    final resolvedUserId = await _resolveDomainUserId();

    try {
      final response = await _client.rpc(
        'get_place_details_v2',
        params: {
          'p_place_id': placeId,
          'p_user_id': resolvedUserId,
        },
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }

      throw StateError('Unexpected get_place_details_v2 response');
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================
  // DETAILS META (CONTENT ONLY)
  // ===========================================================

  @override
  Future<Map<String, dynamic>> getPlaceDetailsMeta({
    required String placeId,
  }) async {
    try {
      final response = await _client.rpc(
        'get_place_details_meta_v1',
        params: {
          'p_place_id': placeId,
        },
      );

      if (response is Map) {
        return Map<String, dynamic>.from(response);
      }

      if (response is List && response.isNotEmpty && response.first is Map) {
        return Map<String, dynamic>.from(response.first as Map);
      }

      throw StateError('Unexpected get_place_details_meta_v1 response');
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================
  // VOTE
  // ===========================================================

  @override
  Future<Map<String, dynamic>> votePlace({
    required String placeId,
    required int value,
  }) async {
    final resolvedUserId = await _resolveDomainUserId();

    try {
      await _client.rpc(
        'vote_place_v1',
        params: {
          'p_place_id': placeId,
          'p_user_id': resolvedUserId,
          'p_value': value,
        },
      );

      final details = await getPlaceDetails(placeId: placeId);

      // 🔴 LIVE INVALIDATION EMIT
      _invalidationController.add(null);

      return details;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<List<PlaceDto>> getMyPlaces() async {
    final resolvedUserId = await _resolveDomainUserId();

    if (resolvedUserId.isEmpty) {
      return [];
    }

    final geo = GeoService.instance.current.value;

    final response = await _client.rpc(
      'get_my_places_v1',
      params: {
        'p_user_id': resolvedUserId,
        if (geo?.lat != null) 'p_lat': geo!.lat,
        if (geo?.lng != null) 'p_lng': geo!.lng,
      },
    );

    Map<String, dynamic> data;

    if (response is Map) {
      data = Map<String, dynamic>.from(response);
    } else if (response is List &&
        response.isNotEmpty &&
        response.first is Map) {
      data = Map<String, dynamic>.from(response.first as Map);
    } else {
      return [];
    }

    final items = (data['items'] as List?) ?? const [];

    return items
        .whereType<Map>()
        .map((e) => PlaceDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Future<void> toggleSavedPlace(String placeId) async {
    final userId = await _resolveDomainUserId();

    await _client.rpc(
      'toggle_saved_place_v1',
      params: {
        'p_place_id': placeId,
        'p_user_id': userId,
      },
    );

    // canonical invalidation for MyPlaces + other listeners
    _invalidationController.add(null);
  }

  @override
  Future<Map<String, dynamic>> createPlaceSubmission({
    required String title,
    required String category,
    required String city,
    required String street,
    required String house,
    String? website,
  }) async {
    final resolvedUserId = await _resolveDomainUserId();

    try {
      final response = await _client.rpc(
        'create_place_submission_v1',
        params: {
          'p_app_user_id': resolvedUserId,
          'p_title': title,
          'p_category': category,
          'p_city': city,
          'p_street': street,
          'p_house': house,
          'p_website': website,
        },
      );

      final data = _expectJsonMap('create_place_submission_v1', response);

      _invalidationController.add(null);

      return data;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> createPlaceSubmissionAndAddToPlan({
    required String planId,
    required String title,
    required String category,
    required String city,
    required String street,
    required String house,
    String? website,
  }) async {
    final resolvedUserId = await _resolveDomainUserId();

    try {
      final response = await _client.rpc(
        'create_place_submission_and_add_to_plan_v1',
        params: {
          'p_app_user_id': resolvedUserId,
          'p_plan_id': planId,
          'p_title': title,
          'p_category': category,
          'p_city': city,
          'p_street': street,
          'p_house': house,
          'p_website': website,
        },
      );

      final data = _expectJsonMap(
        'create_place_submission_and_add_to_plan_v1',
        response,
      );

      // submission was created canonically even when added_to_plan=false
      _invalidationController.add(null);

      return data;
    } catch (e) {
      rethrow;
    }
  }
}
