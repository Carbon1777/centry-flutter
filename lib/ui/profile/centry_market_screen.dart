import 'package:flutter/material.dart';

class CentryMarketScreen extends StatelessWidget {
  const CentryMarketScreen({super.key});

  void _openTokensRules(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: colors.surface,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Правила начисления Tokens', style: text.titleLarge),
                const SizedBox(height: 12),
                Text(
                  'Здесь будет описание правил начисления Tokens.\n'
                  'Контент будет добавлен позже.',
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurface.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Закрыть'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CentryMarket'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.outline,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on_outlined,
                    size: 18,
                    color: colors.onSurface,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Tokens  —',
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),

            /// Кнопка правил
            Align(
              alignment: Alignment.topRight,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openTokensRules(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.outline,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Tokens · правила',
                        style: text.bodyMedium?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            /// 🔹 Регулируем высоту тут
            const Spacer(flex: 1), // было 2 → теперь выше

            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CentryMarket',
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Откроется с релизом проекта.\n'
                    'На этапе бета-тестирования недоступен.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurface.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Токены можно получать и копить уже сейчас \n'
                    'они сохранятся и будут доступны после открытия.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurface.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 3),
          ],
        ),
      ),
    );
  }
}
