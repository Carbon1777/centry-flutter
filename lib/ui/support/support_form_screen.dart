import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/support/support_repository_impl.dart';

class SupportFormScreen extends StatefulWidget {
  final String sessionId;
  final String direction; // SUGGESTION | COMPLAINT
  final String appUserId;

  const SupportFormScreen({
    super.key,
    required this.sessionId,
    required this.direction,
    required this.appUserId,
  });

  @override
  State<SupportFormScreen> createState() => _SupportFormScreenState();
}

class _SupportFormScreenState extends State<SupportFormScreen> {
  final _controller = TextEditingController();
  final _repo = SupportRepositoryImpl(Supabase.instance.client);

  bool _sending = false;
  bool _submitted = false;
  String? _systemMessage;

  bool get _isSuggestion => widget.direction == 'SUGGESTION';

  String get _title => _isSuggestion ? 'Предложение' : 'Жалоба';

  String get _hint => _isSuggestion
      ? 'Опишите ваше предложение...'
      : 'Опишите вашу жалобу...';

  String get _subtitle => _isSuggestion
      ? 'Расскажите, что можно улучшить в Centry'
      : 'Опишите проблему — мы обязательно разберёмся';

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    if (text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Текст слишком короткий')),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final result = _isSuggestion
          ? await _repo.submitSuggestion(
              sessionId: widget.sessionId, text: text)
          : await _repo.submitComplaint(
              sessionId: widget.sessionId, text: text);

      if (!mounted) return;
      setState(() {
        _submitted = true;
        _systemMessage = result.systemMessage;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _submitted ? _buildSuccess(theme) : _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: theme.textTheme.labelMedium,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.cardColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.cardColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: theme.primaryColor),
                ),
                filled: true,
                fillColor: theme.cardColor,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _sending ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Отправить',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _buildSuccess(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.green,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _systemMessage ?? 'Отправлено',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Вернуться',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
