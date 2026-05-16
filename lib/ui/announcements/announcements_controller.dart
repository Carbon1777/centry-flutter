import 'package:flutter/widgets.dart';

import '../../data/announcements/announcement_dto.dart';
import '../../data/announcements/announcements_repository.dart';
import 'announcement_modal.dart';

/// Контроллер очереди новостных модалок Centry.
///
/// Single-instance — защищает от двойного показа стопки при повторных
/// вызовах (token refresh, resume, push deep link).
///
/// Канон последовательности:
/// 1. modal_event_queue разгребается первым (продуктовые модалки приоритетнее).
/// 2. Затем [pumpUnread] показывает все непрочитанные announcements стопкой.
/// 3. Push c `announcement_id` ходит через [showById] — минует очередь,
///    показывает конкретную новость поверх текущего экрана.
class AnnouncementsController {
  AnnouncementsController._();
  static final AnnouncementsController instance = AnnouncementsController._();

  AnnouncementsRepository? _repo;

  /// Глобальный флаг — защищает от двойного показа стопки при
  /// конкурентных триггерах (resume / auth refresh / push).
  bool _pumping = false;
  bool _pumpRerunRequested = false;

  void attachRepository(AnnouncementsRepository repository) {
    _repo = repository;
  }

  /// Вытаскивает все непрочитанные новости и показывает их по одной.
  /// После закрытия каждой — markRead. Если в процессе пришёл новый
  /// триггер — запускаем pump ещё раз после завершения текущего.
  Future<void> pumpUnread({required BuildContext context}) async {
    final repo = _repo;
    if (repo == null) return;

    if (_pumping) {
      _pumpRerunRequested = true;
      return;
    }
    _pumping = true;

    try {
      await _doPump(context: context, repo: repo);
    } finally {
      _pumping = false;
      if (_pumpRerunRequested) {
        _pumpRerunRequested = false;
        // ignore: use_build_context_synchronously
        if (context.mounted) {
          // Запускаем повторный pump без await — не блокируем хвост.
          // Безопасно: _pumping снова станет true перед work'ом.
          pumpUnread(context: context);
        }
      }
    }
  }

  Future<void> _doPump({
    required BuildContext context,
    required AnnouncementsRepository repo,
  }) async {
    List<AnnouncementDto> items;
    try {
      items = await repo.fetchUnread();
    } catch (e, st) {
      debugPrint('[Announcements] fetchUnread error: $e\n$st');
      return;
    }
    if (items.isEmpty) return;

    debugPrint('[Announcements] pumping ${items.length} unread');
    for (final item in items) {
      if (!context.mounted) return;
      await AnnouncementModal.show(context, item);
      try {
        await repo.markRead(item.id);
      } catch (e) {
        debugPrint('[Announcements] markRead(${item.id}) error: $e');
      }
    }
  }

  /// Открывает конкретную новость по id (для push deep link).
  /// Если новость удалена/закончилась — тихо ничего не делает.
  Future<void> showById({
    required BuildContext context,
    required String announcementId,
  }) async {
    final repo = _repo;
    if (repo == null) return;
    AnnouncementDto? dto;
    try {
      dto = await repo.fetchById(announcementId);
    } catch (e) {
      debugPrint('[Announcements] fetchById($announcementId) error: $e');
      return;
    }
    if (dto == null) {
      debugPrint('[Announcements] announcement $announcementId not found / inactive');
      return;
    }
    if (!context.mounted) return;
    await AnnouncementModal.show(context, dto);
    try {
      await repo.markRead(announcementId);
    } catch (e) {
      debugPrint('[Announcements] markRead($announcementId) error: $e');
    }
  }
}
