import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/feed/feed_place_dto.dart';
import '../../../data/feed/feed_repository.dart';
import '../../../data/places/places_repository.dart';
import '../../../features/places/details/place_details_dialog.dart';

String _categoryLabel(String category) {
  switch (category) {
    case 'restaurant':
      return 'Ресторан';
    case 'bar':
      return 'Бар';
    case 'nightclub':
      return 'Ночной клуб';
    case 'cinema':
      return 'Кинотеатр';
    case 'theatre':
      return 'Театр';
    default:
      return 'Место';
  }
}

/// Открывает детали места из ленты.
/// Копирует все механики PlaceDetailsDialog + добавляет feed-блоки.
Future<void> showFeedPlaceDetailSheet({
  required BuildContext context,
  required FeedPlaceDto place,
  required PlacesRepository placesRepository,
  required FeedRepository feedRepository,
  String? appUserId,
}) async {
  // photo_url из get_feed_nearby — это storage_key из place_enrichment
  final storageKey = place.photoStorageKey;
  final photoUrl = storageKey != null && storageKey.isNotEmpty
      ? Supabase.instance.client.storage.from('brand-media').getPublicUrl(storageKey)
      : null;

  await showDialog<void>(
    context: context,
    builder: (_) => PlaceDetailsDialog(
      repository: placesRepository,
      placeId: place.placeId,
      title: place.name,
      typeLabel: _categoryLabel(place.category),
      address: '',
      lat: place.lat ?? 0,
      lng: place.lng ?? 0,
      previewMediaUrl: photoUrl,
      previewStorageKey: storageKey,
      metroName: place.metroName,
      metroDistanceM: place.metroDistanceMeters,
      // Feed-specific
      feedCountPlans: place.countPlans,
      feedInterestedCount: place.interestedCount,
      feedPlannedCount: place.plannedCount,
      feedVisitedCount: place.visitedCount,
      feedRepository: feedRepository,
    ),
  );
}
