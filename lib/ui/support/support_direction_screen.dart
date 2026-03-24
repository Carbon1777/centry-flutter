import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/support/support_repository_impl.dart';
import 'support_question_chat_screen.dart';
import 'support_form_screen.dart';

class SupportDirectionScreen extends StatefulWidget {
  final String appUserId;

  const SupportDirectionScreen({super.key, required this.appUserId});

  @override
  State<SupportDirectionScreen> createState() => _SupportDirectionScreenState();
}

class _SupportDirectionScreenState extends State<SupportDirectionScreen> {
  bool _loading = false;

  Future<void> _onDirectionTap(String direction) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final repo = SupportRepositoryImpl(Supabase.instance.client);
      final result = await repo.createSession(direction: direction);

      if (!mounted) return;

      if (direction == 'QUESTION') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SupportQuestionChatScreen(
              sessionId: result.sessionId,
              appUserId: widget.appUserId,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SupportFormScreen(
              sessionId: result.sessionId,
              direction: direction,
              appUserId: widget.appUserId,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поддержка'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Чем можем помочь?',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Выберите тип обращения',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  _DirectionCard(
                    icon: Icons.help_outline_rounded,
                    title: 'Вопросы',
                    subtitle: 'Задайте вопрос — AI-помощник ответит на основе базы знаний',
                    onTap: () => _onDirectionTap('QUESTION'),
                  ),
                  const SizedBox(height: 12),
                  _DirectionCard(
                    icon: Icons.lightbulb_outline_rounded,
                    title: 'Предложения',
                    subtitle: 'Расскажите, что можно улучшить в приложении',
                    onTap: () => _onDirectionTap('SUGGESTION'),
                  ),
                  const SizedBox(height: 12),
                  _DirectionCard(
                    icon: Icons.flag_outlined,
                    title: 'Жалобы',
                    subtitle: 'Сообщите о проблеме — мы обязательно разберёмся',
                    onTap: () => _onDirectionTap('COMPLAINT'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DirectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: theme.primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.labelMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.iconTheme.color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
