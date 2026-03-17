abstract class AccountDeletionRepository {
  /// Фаза A: перевести аккаунт в PENDING_DELETION, создать deletion job.
  /// Возвращает job_id.
  /// Идемпотентна: повторный вызов не ломает состояние.
  Future<String> requestDeletion({String? reason});

  /// Фаза B + удаление auth.users: вызвать Edge Function delete-auth-user.
  /// Запускает полный pipeline очистки данных и удаляет запись auth.users.
  Future<void> finalizeAuthDeletion();
}
