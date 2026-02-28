import 'package:flutter/material.dart';

class PlanMemberRemovedInfoModal extends StatelessWidget {
  final String title;
  final String body;

  const PlanMemberRemovedInfoModal({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        title,
        style: TextStyle(
          color: cs.error,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Ок'),
        ),
      ],
    );
  }
}
