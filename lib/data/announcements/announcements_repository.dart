import 'announcement_dto.dart';

/// Контракт доступа к серверно-управляемым новостным модалкам Centry.
///
/// Сервер — единственный источник истины: клиент только дёргает RPC и
/// рендерит готовые snapshot-данные. См. CLAUDE.md §5 (server-first).
abstract class AnnouncementsRepository {
  /// Возвращает все активные непрочитанные текущим пользователем новости.
  /// Сортировка: priority DESC, starts_at DESC (как на сервере).
  Future<List<AnnouncementDto>> fetchUnread();

  /// Помечает новость как прочитанную для текущего пользователя.
  /// Идемпотентно — повторный вызов не упадёт.
  Future<void> markRead(String announcementId);

  /// Возвращает конкретную активную новость или null, если она
  /// удалена / закончилась / ещё не началась.
  /// Используется push-обработчиком при deep link на конкретную новость.
  Future<AnnouncementDto?> fetchById(String announcementId);
}
