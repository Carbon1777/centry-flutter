import 'feed_place_dto.dart';
import 'plan_shell_dto.dart';

abstract class FeedRepository {
  /// Загрузить ленту мест рядом с [lat]/[lng].
  /// Если координаты null — сервер вернёт рандомную выдачу.
  Future<List<FeedPlaceDto>> getFeedNearby({
    double? lat,
    double? lng,
    int limit = 25,
  });

  /// Оболочки активных планов для места [placeId].
  Future<List<PlanShellDto>> getPlanShells(String placeId);
}
