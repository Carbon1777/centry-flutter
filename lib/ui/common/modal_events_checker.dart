import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/attention_signs/attention_signs_repository_impl.dart';
import '../../data/modal_events/modal_event_dto.dart';
import '../../data/modal_events/modal_events_repository_impl.dart';
import '../../ui/friends/friends_refresh_bus.dart';
import 'center_toast.dart';

enum _DialogResult { accept, decline }

/// Guard: prevents concurrent runs of [checkAndShowModalEvents].
bool _modalEventsCheckInProgress = false;

/// Проверяет очередь модальных событий и показывает их по одному (старые → новые).
/// Вызывать из живого BuildContext (например, postFrameCallback).
///
/// [onOpenPlan] — опциональный коллбэк для открытия деталей плана:
/// вызывается при принятии PLAN_INTERNAL_INVITE или нажатии «Перейти к плану».
Future<void> checkAndShowModalEvents({
  required BuildContext context,
  required String appUserId,
  void Function(String planId)? onOpenPlan,
}) async {
  // Prevent re-entrant / concurrent runs — only one checker at a time.
  if (_modalEventsCheckInProgress) {
    debugPrint('[ModalEvents] checkAndShowModalEvents SKIPPED — already in progress');
    return;
  }
  _modalEventsCheckInProgress = true;

  try {
    await _doCheckAndShow(
      context: context,
      appUserId: appUserId,
      onOpenPlan: onOpenPlan,
    );
  } finally {
    _modalEventsCheckInProgress = false;
  }
}

Future<void> _doCheckAndShow({
  required BuildContext context,
  required String appUserId,
  void Function(String planId)? onOpenPlan,
}) async {
  final repo = ModalEventsRepositoryImpl(Supabase.instance.client);
  final attentionRepo = AttentionSignsRepositoryImpl(Supabase.instance.client);

  List<ModalEventDto> events;
  try {
    events = await repo.getPendingEvents(appUserId: appUserId);
  } catch (e, st) {
    debugPrint('[ModalEvents] getPendingEvents ERROR: $e\n$st');
    return;
  }

  debugPrint('[ModalEvents] got ${events.length} pending events for user=$appUserId');

  for (final event in events) {
    if (!context.mounted) {
      debugPrint('[ModalEvents] context unmounted, stopping');
      return;
    }
    debugPrint('[ModalEvents] showing modal for type=${event.eventType}, id=${event.eventId}');
    await _showEventModal(
      context: context,
      appUserId: appUserId,
      event: event,
      repo: repo,
      attentionRepo: attentionRepo,
      onOpenPlan: onOpenPlan,
    );
  }
}

Future<void> _showEventModal({
  required BuildContext context,
  required String appUserId,
  required ModalEventDto event,
  required ModalEventsRepositoryImpl repo,
  required AttentionSignsRepositoryImpl attentionRepo,
  void Function(String planId)? onOpenPlan,
}) async {
  final p = event.payload;
  final nick = event.actorNickname ?? '—';
  final type = event.eventType;

  // ── ATTENTION_SIGN ──────────────────────────────────────────────────────────
  if (type == 'ATTENTION_SIGN_ACCEPTED' || type == 'ATTENTION_SIGN_DECLINED') {
    final isAccepted = type == 'ATTENTION_SIGN_ACCEPTED';
    final alreadyFriends = p['already_friends'] == true;
    final submissionId = p['submission_id'] as String?;
    final showInviteButton = isAccepted && !alreadyFriends && submissionId != null;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModalEventDialog(
        nick: nick,
        isAccepted: isAccepted,
        stickerUrl: event.stickerUrl,
        showInviteButton: showInviteButton,
        onInvite: showInviteButton ? () => Navigator.of(ctx).pop('invite') : null,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );

    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}

    if (result == 'invite' && submissionId != null && context.mounted) {
      try {
        final ok = await attentionRepo.useFriendInviteRightAndRequest(
          appUserId: appUserId,
          submissionId: submissionId,
        );
        if (ok && context.mounted) {
          showCenterToast(context, message: 'Запрос в друзья отправлен');
        }
      } catch (_) {}
    }
    return;
  }

  // ── FRIEND_REQUEST_RECEIVED ────────────────────────────────────────────────
  if (type == 'FRIEND_REQUEST_RECEIVED') {
    final requestId = (p['request_id'] ?? '').toString();
    final result = await _showFriendRequestDialog(
      context: context,
      nick: nick,
      avatarUrl: event.actorAvatarUrl,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    if (!context.mounted) return;
    if (result == _DialogResult.accept && requestId.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'accept_friend_request_v2',
          params: {'p_user_id': appUserId, 'p_request_id': requestId},
        );
        FriendsRefreshBus.ping();
        if (context.mounted) showCenterToast(context, message: 'Запрос принят');
      } catch (_) {}
    } else if (result == _DialogResult.decline && requestId.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'decline_friend_request_v2',
          params: {'p_user_id': appUserId, 'p_request_id': requestId},
        );
        FriendsRefreshBus.ping();
      } catch (_) {}
    }
    return;
  }

  // ── FRIEND_REQUEST_ACCEPTED ────────────────────────────────────────────────
  if (type == 'FRIEND_REQUEST_ACCEPTED') {
    await _showInfoDialog(
      context: context,
      title: 'Запрос в друзья принят',
      body: '«$nick» принял ваш запрос в друзья.',
      titleColor: Colors.green,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    FriendsRefreshBus.ping();
    return;
  }

  // ── FRIEND_REQUEST_DECLINED ────────────────────────────────────────────────
  if (type == 'FRIEND_REQUEST_DECLINED') {
    await _showInfoDialog(
      context: context,
      title: 'Запрос в друзья отклонён',
      body: '«$nick» отклонил ваш запрос в друзья.',
      titleColor: Colors.red,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── FRIEND_REMOVED ─────────────────────────────────────────────────────────
  if (type == 'FRIEND_REMOVED') {
    await _showInfoDialog(
      context: context,
      title: 'Вас удалили из друзей',
      body: '«$nick» удалил вас из списка друзей.',
      titleColor: Colors.red,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    FriendsRefreshBus.ping();
    return;
  }

  // ── PLAN_INTERNAL_INVITE ───────────────────────────────────────────────────
  if (type == 'PLAN_INTERNAL_INVITE') {
    final inviteId = (p['invite_id'] ?? '').toString();
    final planId = (p['plan_id'] ?? '').toString();
    final planTitle = (p['plan_title'] ?? '').toString();

    // Consume FIRST — server checks if invite is still PENDING.
    // Returns skip=true if invite is expired or cancelled → don't show dialog.
    bool skip = false;
    try {
      skip = await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    if (skip || !context.mounted) return;

    final body = planTitle.isNotEmpty
        ? '«$nick» приглашает вас в план «$planTitle».'
        : '«$nick» приглашает вас в план.';
    final result = await _showChoiceDialog(
      context: context,
      title: 'Приглашение в план',
      body: body,
      acceptLabel: 'Принять',
      declineLabel: 'Отклонить',
    );
    if (!context.mounted) return;
    if (result == _DialogResult.accept && inviteId.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'respond_plan_internal_invite_v1',
          params: {
            'p_app_user_id': appUserId,
            'p_invite_id': inviteId,
            'p_action': 'ACCEPT',
          },
        );
        if (planId.isNotEmpty) onOpenPlan?.call(planId);
      } catch (e) {
        if (context.mounted) {
          showCenterToast(context, message: 'Ошибка: $e', isError: true);
        }
      }
    } else if (result == _DialogResult.decline && inviteId.isNotEmpty) {
      try {
        await Supabase.instance.client.rpc(
          'respond_plan_internal_invite_v1',
          params: {
            'p_app_user_id': appUserId,
            'p_invite_id': inviteId,
            'p_action': 'DECLINE',
          },
        );
        if (context.mounted) showCenterToast(context, message: 'Приглашение отклонено');
      } catch (e) {
        if (context.mounted) {
          showCenterToast(context, message: 'Ошибка: $e', isError: true);
        }
      }
    }
    return;
  }

  // ── PLAN_DELETED ───────────────────────────────────────────────────────────
  if (type == 'PLAN_DELETED') {
    final planTitle = (p['plan_title'] ?? '').toString();
    final body = planTitle.isNotEmpty
        ? '«$nick» удалил план «$planTitle».'
        : 'Один из ваших планов был удалён.';
    await _showInfoDialog(context: context, title: 'План удалён', body: body);
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── PLAN_MEMBER_LEFT ───────────────────────────────────────────────────────
  if (type == 'PLAN_MEMBER_LEFT') {
    final planTitle = (p['plan_title'] ?? '').toString();
    final body = planTitle.isNotEmpty
        ? '«$nick» покинул план «$planTitle».'
        : '«$nick» покинул план.';
    await _showInfoDialog(
      context: context,
      title: 'Участник покинул план',
      body: body,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── PLAN_MEMBER_REMOVED ────────────────────────────────────────────────────
  if (type == 'PLAN_MEMBER_REMOVED') {
    final planTitle = (p['plan_title'] ?? '').toString();
    final body = planTitle.isNotEmpty
        ? '«$nick» исключил вас из плана «$planTitle».'
        : '«$nick» исключил вас из плана.';
    await _showInfoDialog(
      context: context,
      title: 'Вас исключили из плана',
      body: body,
      titleColor: Colors.red,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── PLAN_MEMBER_JOINED_BY_INVITE ───────────────────────────────────────────
  if (type == 'PLAN_MEMBER_JOINED_BY_INVITE') {
    final planTitle = (p['plan_title'] ?? '').toString();
    final body = planTitle.isNotEmpty
        ? '«$nick» присоединился к плану «$planTitle».'
        : '«$nick» присоединился к плану.';
    await _showInfoDialog(context: context, title: 'Новый участник', body: body);
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── PLAN_VOTING_REMINDER_* и PLAN_OWNER_PRIORITY_* ────────────────────────
  if (type == 'PLAN_VOTING_REMINDER_DATE' ||
      type == 'PLAN_VOTING_REMINDER_PLACE' ||
      type == 'PLAN_VOTING_REMINDER_BOTH' ||
      type == 'PLAN_OWNER_PRIORITY_DATE' ||
      type == 'PLAN_OWNER_PRIORITY_PLACE' ||
      type == 'PLAN_OWNER_PRIORITY_BOTH') {
    final planId = (p['plan_id'] ?? '').toString();
    final title = _resolveScheduledTitle(type, p);
    final body = _resolveScheduledBody(type, p);
    final result = await _showScheduledDialog(
      context: context,
      title: title,
      body: body,
      showGoToPlan: planId.isNotEmpty && onOpenPlan != null,
    );
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    if (result == _DialogResult.accept && planId.isNotEmpty && context.mounted) {
      onOpenPlan?.call(planId);
    }
    return;
  }

  // ── PLAN_EVENT_REMINDER_24H ────────────────────────────────────────────────
  if (type == 'PLAN_EVENT_REMINDER_24H') {
    final title = _resolveScheduledTitle(type, p);
    final body = _resolveScheduledBody(type, p);
    await _showInfoDialog(context: context, title: title, body: body);
    try {
      await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
    } catch (_) {}
    return;
  }

  // ── Неизвестный тип — consume без показа ──────────────────────────────────
  try {
    await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
  } catch (_) {}
}

// ── Helpers: scheduled notification text ───────────────────────────────────

String _resolveScheduledTitle(String type, Map<String, dynamic> p) {
  final serverTitle = (p['title'] ?? '').toString().trim();
  if (serverTitle.isNotEmpty) return serverTitle;
  switch (type) {
    case 'PLAN_VOTING_REMINDER_DATE':
      return 'Выберите дату';
    case 'PLAN_VOTING_REMINDER_PLACE':
      return 'Выберите место';
    case 'PLAN_VOTING_REMINDER_BOTH':
      return 'Завершите голосование';
    case 'PLAN_OWNER_PRIORITY_DATE':
      return 'Выберите приоритетную дату';
    case 'PLAN_OWNER_PRIORITY_PLACE':
      return 'Выберите приоритетное место';
    case 'PLAN_OWNER_PRIORITY_BOTH':
      return 'Выберите приоритет';
    case 'PLAN_EVENT_REMINDER_24H':
      return 'Мероприятие';
    default:
      return 'Уведомление';
  }
}

String _resolveScheduledBody(String type, Map<String, dynamic> p) {
  final serverBody = (p['body'] ?? '').toString().trim();
  if (serverBody.isNotEmpty) return serverBody;
  final plan = (p['plan_title'] ?? '').toString().trim();
  final eventDateTime = (p['event_datetime_label'] ?? '').toString().trim();
  final place = (p['place_title'] ?? '').toString().trim();
  switch (type) {
    case 'PLAN_VOTING_REMINDER_DATE':
      return plan.isNotEmpty
          ? 'Вы еще не проголосовали за дату в плане «$plan».'
          : 'Вы еще не проголосовали за дату.';
    case 'PLAN_VOTING_REMINDER_PLACE':
      return plan.isNotEmpty
          ? 'Вы еще не проголосовали за место в плане «$plan».'
          : 'Вы еще не проголосовали за место.';
    case 'PLAN_VOTING_REMINDER_BOTH':
      return plan.isNotEmpty
          ? 'Вы еще не выбрали дату и место в плане «$plan».'
          : 'Вы еще не выбрали дату и место.';
    case 'PLAN_OWNER_PRIORITY_DATE':
      return plan.isNotEmpty
          ? 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по дате еще не определен. '
              'Выберите приоритетную дату среди лидирующих вариантов.'
          : 'Победитель по дате еще не определен. '
              'Выберите приоритетную дату среди лидирующих вариантов.';
    case 'PLAN_OWNER_PRIORITY_PLACE':
      return plan.isNotEmpty
          ? 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по месту еще не определен. '
              'Выберите приоритетное место среди лидирующих вариантов.'
          : 'Победитель по месту еще не определен. '
              'Выберите приоритетное место среди лидирующих вариантов.';
    case 'PLAN_OWNER_PRIORITY_BOTH':
      return plan.isNotEmpty
          ? 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по дате и месту еще не определен. '
              'Выберите приоритетные дату и место среди лидирующих вариантов.'
          : 'Победитель по дате и месту еще не определен. '
              'Выберите приоритетные дату и место среди лидирующих вариантов.';
    case 'PLAN_EVENT_REMINDER_24H':
      if (plan.isNotEmpty && eventDateTime.isNotEmpty && place.isNotEmpty) {
        return 'По плану «$plan» $eventDateTime у вас запланировано мероприятие в «$place».';
      }
      if (plan.isNotEmpty && eventDateTime.isNotEmpty) {
        return 'По плану «$plan» $eventDateTime у вас запланировано мероприятие.';
      }
      return 'У вас запланировано мероприятие.';
    default:
      return '';
  }
}

// ── Dialog helpers ──────────────────────────────────────────────────────────

Future<void> _showInfoDialog({
  required BuildContext context,
  required String title,
  required String body,
  Color? titleColor,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(
        title,
        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
      ),
      content: body.isNotEmpty
          ? ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: Text(
                body,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.3,
                    ),
              ),
            )
          : null,
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

Future<_DialogResult?> _showChoiceDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String acceptLabel,
  required String declineLabel,
}) {
  return showDialog<_DialogResult>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
        child: Text(
          body,
          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                height: 1.3,
              ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx, rootNavigator: true).pop(_DialogResult.decline),
          child: Text(declineLabel),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx, rootNavigator: true).pop(_DialogResult.accept),
          child: Text(acceptLabel),
        ),
      ],
    ),
  );
}

Future<_DialogResult?> _showFriendRequestDialog({
  required BuildContext context,
  required String nick,
  String? avatarUrl,
}) {
  return showDialog<_DialogResult>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: const Text('Запрос в друзья'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatarUrl != null && avatarUrl.isNotEmpty) ...[
              CachedNetworkImage(
                imageUrl: avatarUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                imageBuilder: (_, img) =>
                    CircleAvatar(radius: 28, backgroundImage: img),
                errorWidget: (_, __, ___) =>
                    const CircleAvatar(radius: 28, child: Icon(Icons.person)),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              '«$nick» хочет добавить вас в друзья.',
              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.3,
                  ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx, rootNavigator: true).pop(_DialogResult.decline),
          child: const Text('Отклонить'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(ctx, rootNavigator: true).pop(_DialogResult.accept),
          child: const Text('Принять'),
        ),
      ],
    ),
  );
}

/// Для PLAN_VOTING_REMINDER_* и PLAN_OWNER_PRIORITY_* —
/// показывает «Перейти к плану» (возвращает accept) и «Закрыть» (null).
Future<_DialogResult?> _showScheduledDialog({
  required BuildContext context,
  required String title,
  required String body,
  bool showGoToPlan = false,
}) {
  return showDialog<_DialogResult>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(
        title.isNotEmpty ? title : 'Уведомление',
        style: Theme.of(ctx)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      content: body.isNotEmpty
          ? ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: Text(
                body,
                style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.3,
                    ),
              ),
            )
          : null,
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (showGoToPlan)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_DialogResult.accept),
            child: const Text('Перейти к плану'),
          ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

// ── Existing ATTENTION_SIGN dialog widget (unchanged) ──────────────────────

class _ModalEventDialog extends StatelessWidget {
  final String nick;
  final bool isAccepted;
  final String? stickerUrl;
  final bool showInviteButton;
  final VoidCallback? onInvite;
  final VoidCallback onClose;

  const _ModalEventDialog({
    required this.nick,
    required this.isAccepted,
    required this.stickerUrl,
    required this.showInviteButton,
    this.onInvite,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = isAccepted
        ? '$nick принял ваш знак внимания!'
        : '$nick отклонил ваш знак внимания';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stickerUrl != null) ...[
            CachedNetworkImage(
              imageUrl: stickerUrl!,
              width: 80,
              height: 80,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => Icon(
                Icons.star_outline,
                size: 64,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        if (showInviteButton)
          TextButton(
            onPressed: onInvite,
            child: const Text('Пригласить в друзья'),
          ),
        TextButton(
          onPressed: onClose,
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
