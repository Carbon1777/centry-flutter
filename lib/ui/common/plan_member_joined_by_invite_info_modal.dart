import 'package:flutter/material.dart';

/// Info-only modal for owner: "A participant joined the plan via invite link".
/// UI-only: no business logic here.
///
/// IMPORTANT: keep geometry identical to other in-app info modals.
class PlanMemberJoinedByInviteInfoModal extends StatelessWidget {
  final String title;
  final String body;

  const PlanMemberJoinedByInviteInfoModal({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = title.trim().isNotEmpty
        ? title.trim()
        : 'Участник вступил в план по Invite';
    final b = body.trim();

    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color.fromARGB(255, 80, 184, 84),
          fontWeight: FontWeight.w700,
        );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(t, style: titleStyle),
      content: b.isNotEmpty
          ? ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: Text(
                b,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.3,
                    ),
              ),
            )
          : null,
      actionsAlignment: MainAxisAlignment.center,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
