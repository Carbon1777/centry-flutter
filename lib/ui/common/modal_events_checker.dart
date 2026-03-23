import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/attention_signs/attention_signs_repository_impl.dart';
import '../../data/modal_events/modal_event_dto.dart';
import '../../data/modal_events/modal_events_repository_impl.dart';

/// Проверяет очередь модальных событий и показывает их по одному (старые → новые).
/// Вызывать из живого BuildContext (например, postFrameCallback).
Future<void> checkAndShowModalEvents({
  required BuildContext context,
  required String appUserId,
}) async {
  final repo = ModalEventsRepositoryImpl(Supabase.instance.client);
  final attentionRepo = AttentionSignsRepositoryImpl(Supabase.instance.client);

  List<ModalEventDto> events;
  try {
    events = await repo.getPendingEvents(appUserId: appUserId);
  } catch (_) {
    return;
  }

  for (final event in events) {
    if (!context.mounted) return;
    await _showEventModal(
      context: context,
      appUserId: appUserId,
      event: event,
      repo: repo,
      attentionRepo: attentionRepo,
    );
  }
}

Future<void> _showEventModal({
  required BuildContext context,
  required String appUserId,
  required ModalEventDto event,
  required ModalEventsRepositoryImpl repo,
  required AttentionSignsRepositoryImpl attentionRepo,
}) async {
  final nick = event.actorNickname ?? '—';
  final isAccepted = event.eventType == 'ATTENTION_SIGN_ACCEPTED';
  final alreadyFriends = event.payload['already_friends'] == true;
  final submissionId = event.payload['submission_id'] as String?;

  final showInviteButton = isAccepted && !alreadyFriends && submissionId != null;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ModalEventDialog(
      nick: nick,
      isAccepted: isAccepted,
      stickerUrl: event.stickerUrl,
      showInviteButton: showInviteButton,
      onInvite: showInviteButton
          ? () async {
              Navigator.of(ctx).pop();
              try {
                await attentionRepo.useFriendInviteRight(
                  appUserId: appUserId,
                  submissionId: submissionId,
                );
              } catch (_) {}
            }
          : null,
      onClose: () => Navigator.of(ctx).pop(),
    ),
  );

  // Помечаем как SHOWN в любом случае
  try {
    await repo.consumeEvent(appUserId: appUserId, eventId: event.eventId);
  } catch (_) {}
}

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
