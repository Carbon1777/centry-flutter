import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/account/account_deletion_repository_impl.dart';
import '../../data/local/user_snapshot_storage.dart';

/// 2-этапный модал удаления аккаунта.
/// Этап 1 — предупреждение со списком последствий.
/// Этап 2 — подтверждение с чекбоксом и деструктивной кнопкой.
///
/// При успехе вызывает [onAccountDeleted] — коллбэк в app.dart для разлогина.
class DeleteAccountModal extends StatefulWidget {
  final VoidCallback onAccountDeleted;

  const DeleteAccountModal({super.key, required this.onAccountDeleted});

  @override
  State<DeleteAccountModal> createState() => _DeleteAccountModalState();
}

class _DeleteAccountModalState extends State<DeleteAccountModal> {
  // Этап: 0 — предупреждение, 1 — подтверждение, 2 — загрузка, 3 — ошибка
  int _step = 0;
  bool _confirmed = false;
  String? _errorText;

  Future<void> _submit() async {
    setState(() {
      _step = 2;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;
      final repo = AccountDeletionRepositoryImpl(client);

      // Фаза A: создать job на сервере
      await repo.requestDeletion(reason: 'user_initiated');

      // Фаза B + удаление auth.users: очистить данные и auth запись
      await repo.finalizeAuthDeletion();

      // Очистить локальное хранилище
      await UserSnapshotStorage().clear();

      // Разлогин (сессия уже инвалидирована на сервере, но очищаем локально)
      await client.auth.signOut();

      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onAccountDeleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = 3;
        _errorText = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Запрещаем закрытие свайпом во время загрузки
      canPop: _step != 2,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return switch (_step) {
      0 => _WarningStep(onNext: () => setState(() => _step = 1)),
      1 => _ConfirmStep(
          confirmed: _confirmed,
          onConfirmChanged: (v) => setState(() => _confirmed = v),
          onSubmit: _confirmed ? _submit : null,
          onBack: () => setState(() => _step = 0),
        ),
      2 => const _LoadingStep(),
      3 => _ErrorStep(
          error: _errorText ?? 'Неизвестная ошибка',
          onRetry: () => setState(() {
            _step = 1;
            _confirmed = false;
          }),
          onClose: () => Navigator.of(context).pop(),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

// ══════════════════════════════════════════════════════════
// Шаг 1 — Предупреждение
// ══════════════════════════════════════════════════════════

class _WarningStep extends StatelessWidget {
  final VoidCallback onNext;

  const _WarningStep({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Удаление аккаунта', style: text.titleLarge),
          const SizedBox(height: 16),
          Text(
            'После удаления аккаунта доступ к нему будет закрыт. Личные данные будут удалены или обезличены. Часть информации может сохраниться в обезличенном виде, если это необходимо для целостности сервиса, безопасности или соблюдения требований законодательства.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 16),
          const _ConsequenceItem(
            icon: Icons.person_off_outlined,
            text: 'Профиль будет удалён, доступ закрыт навсегда',
          ),
          const _ConsequenceItem(
            icon: Icons.delete_outline,
            text: 'Личные данные (имя, email, аватар) будут удалены',
          ),
          const _ConsequenceItem(
            icon: Icons.group_off_outlined,
            text: 'Ваши активные планы будут закрыты',
          ),
          const _ConsequenceItem(
            icon: Icons.chat_bubble_outline,
            text: 'Сообщения в чатах останутся обезличенными',
          ),
          const _ConsequenceItem(
            icon: Icons.monetization_on_outlined,
            text: 'Баланс токенов будет аннулирован',
            isLast: true,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: onNext,
                child: const Text('Продолжить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConsequenceItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isLast;

  const _ConsequenceItem({
    required this.icon,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: textStyle.bodySmall),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Шаг 2 — Подтверждение с чекбоксом
// ══════════════════════════════════════════════════════════

class _ConfirmStep extends StatelessWidget {
  final bool confirmed;
  final ValueChanged<bool> onConfirmChanged;
  final VoidCallback? onSubmit;
  final VoidCallback onBack;

  const _ConfirmStep({
    required this.confirmed,
    required this.onConfirmChanged,
    required this.onSubmit,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Подтверждение удаления', style: text.titleLarge),
          const SizedBox(height: 16),
          Text(
            'Это действие необратимо. После подтверждения аккаунт будет удалён.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: () => onConfirmChanged(!confirmed),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: confirmed,
                    onChanged: (v) => onConfirmChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 11),
                      child: Text(
                        'Я понимаю последствия удаления аккаунта и подтверждаю это действие.',
                        style: text.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Назад'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: onSubmit != null ? colors.error : colors.surfaceContainerHighest,
                  foregroundColor: onSubmit != null ? colors.onError : colors.onSurfaceVariant,
                ),
                onPressed: onSubmit,
                child: const Text('Удалить аккаунт'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Шаг 3 — Загрузка
// ══════════════════════════════════════════════════════════

class _LoadingStep extends StatelessWidget {
  const _LoadingStep();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Аккаунт удаляется...',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Шаг 4 — Ошибка
// ══════════════════════════════════════════════════════════

class _ErrorStep extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  const _ErrorStep({
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ошибка удаления', style: text.titleLarge),
          const SizedBox(height: 12),
          Text(
            'Не удалось удалить аккаунт. Попробуйте ещё раз или обратитесь в поддержку.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(error, style: text.bodySmall),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onClose, child: const Text('Закрыть')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
            ],
          ),
        ],
      ),
    );
  }
}
