import 'package:flutter/material.dart';

import 'plan_chat_avatar.dart';

class PlanChatPresentationMessage {
  final String id;
  final String authorUserId;
  final String authorNickname;
  final bool nicknameHidden;
  final String? avatarUrl;
  final bool avatarHidden;
  final String text;
  final DateTime createdAt;
  final bool isMine;
  final DateTime? editedAt;
  final String? messageKind;
  final DateTime? deletedAt;

  bool get isTombstone =>
      messageKind == 'tombstone' || deletedAt != null;

  const PlanChatPresentationMessage({
    required this.id,
    required this.authorUserId,
    required this.authorNickname,
    this.nicknameHidden = false,
    this.avatarUrl,
    this.avatarHidden = false,
    required this.text,
    required this.createdAt,
    required this.isMine,
    this.editedAt,
    this.messageKind,
    this.deletedAt,
  });
}

class PlanChatMessageBubble extends StatelessWidget {
  final PlanChatPresentationMessage message;
  final VoidCallback? onLongPress;

  const PlanChatMessageBubble({
    super.key,
    required this.message,
    this.onLongPress,
  });

  String _formatMessageDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTombstone = message.isTombstone;
    final isEdited = !isTombstone && message.editedAt != null;

    final bubbleColor = isTombstone
        ? theme.colorScheme.surface.withOpacity(0.40)
        : (message.isMine
            ? const Color(0xFF10233F)
            : theme.colorScheme.surface.withOpacity(0.94));
    final borderColor = isTombstone
        ? Colors.white.withOpacity(0.08)
        : (message.isMine
            ? const Color(0xFF2A62C7).withOpacity(0.50)
            : Colors.white.withOpacity(0.14));
    final nicknameColor = message.isMine
        ? const Color(0xFF7FB0FF)
        : const Color(0xFF8BE4D4);

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment:
            message.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: isTombstone ? 0.35 : 1.0,
                    child: PlanChatAvatar(
                      userId: message.authorUserId,
                      nickname: message.authorNickname,
                      avatarUrl: message.avatarUrl,
                      avatarHidden: message.avatarHidden,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.nicknameHidden ? 'Скрыто' : message.authorNickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: isTombstone
                                ? Colors.white.withOpacity(0.35)
                                : (message.nicknameHidden
                                    ? theme.colorScheme.outline
                                    : nicknameColor),
                            fontStyle: message.nicknameHidden
                                ? FontStyle.italic
                                : FontStyle.normal,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatMessageDateTime(message.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(
                              isTombstone ? 0.35 : 0.68,
                            ),
                            fontWeight: FontWeight.w500,
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (isTombstone)
                Text(
                  'Сообщение удалено',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.35,
                    fontSize: 15.5,
                    color: Colors.white.withOpacity(0.38),
                    fontStyle: FontStyle.italic,
                  ),
                )
              else ...[
                Text(
                  message.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.35,
                    fontSize: 15.5,
                  ),
                ),
                if (isEdited)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Изменено',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withOpacity(0.45),
                        fontWeight: FontWeight.w500,
                        height: 1.0,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }
}
