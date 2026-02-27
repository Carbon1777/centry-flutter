import 'package:flutter/material.dart';

class PlanMemberLeftInfoModal extends StatelessWidget {
  final String title;
  final String body;

  const PlanMemberLeftInfoModal({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(
          color: colorScheme.error,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        body,
        style: theme.textTheme.bodyLarge,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
