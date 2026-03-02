import 'package:flutter/material.dart';

class AddFriendByPublicIdDialog extends StatefulWidget {
  const AddFriendByPublicIdDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (_) => const AddFriendByPublicIdDialog(),
    );
  }

  @override
  State<AddFriendByPublicIdDialog> createState() => _AddFriendByPublicIdDialogState();
}

class _AddFriendByPublicIdDialogState extends State<AddFriendByPublicIdDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) {
      setState(() => _error = 'Введите Public ID');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Добавить в друзья'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          maxLength: 32,
          decoration: InputDecoration(
            labelText: 'Public ID',
            hintText: 'Например: A1B2C3',
            border: const OutlineInputBorder(),
            errorText: _error,
            counterText: '',
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _submit(),
          buildCounter: (
            BuildContext context, {
            required int currentLength,
            required bool isFocused,
            required int? maxLength,
          }) {
            final max = maxLength ?? 0;
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '$currentLength/$max',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Отправить'),
        ),
      ],
    );
  }
}
