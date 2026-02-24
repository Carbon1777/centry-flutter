import 'place_dto.dart';

class PlacesFeedResult {
  final List<PlaceDto> items;
  final bool hasMore;

  PlacesFeedResult({
    required this.items,
    required this.hasMore,
  });
}
