import 'announcement_dto.dart';

/// Контракт доступа к серверно-управляемым новостным модалкам Centry.
///
/// Сервер — единственный источник истины: клиент только дёргает RPC и
/// рендерит готовые snapshot-данные. См. CLAUDE.md §5 (server-first).
abstract class AnnouncementsRepository {
  /// Возвращает все активные непрочитанные новости для [appUserId].
  /// Сортировка: priority DESC, starts_at DESC (как на сервере).
  Future<List<AnnouncementDto>> fetchUnread({required String appUserId});

  /// Помечает новость как прочитанную для [appUserId].
  /// Идемпотентно — повторный вызов не упадёт.
  Future<void> markRead({required String appUserId, required String announcementId});

  /// Возвращает конкретную активную новость или null, если она
  /// удалена / закончилась / ещё не началась.
  /// Используется push-обработчиком при deep link на конкретную новость.
  Future<AnnouncementDto?> fetchById(String announcementId);
}
