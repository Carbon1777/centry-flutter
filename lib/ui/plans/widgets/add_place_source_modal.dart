import 'package:flutter/material.dart';

enum PlanPlaceAddSource {
  generalList,
  myPlaces,
  createOwnPlace,
}

class PlanPlaceAddSourceModal {
  PlanPlaceAddSourceModal._();

  static Future<PlanPlaceAddSource?> show(
    BuildContext context, {
    required String planTitle,
  }) async {
    return showModalBottomSheet<PlanPlaceAddSource>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanPlaceAddSourceSheet(planTitle: planTitle),
    );
  }
}

class _PlanPlaceAddSourceSheet extends StatelessWidget {
  final String planTitle;

  const _PlanPlaceAddSourceSheet({
    required this.planTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Выберите способ добавления места',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'План: «$planTitle»',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                  children: [
                    _SourceCard(
                      icon: Icons.list_alt_outlined,
                      title: 'Из общего списка',
                      subtitle: 'Выбрать место из общего списка мест.',
                      onTap: () => Navigator.of(context).pop(
                        PlanPlaceAddSource.generalList,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SourceCard(
                      icon: Icons.bookmark_border_rounded,
                      title: 'Из списка «Мои места»',
                      subtitle: 'Выбрать место из сохранённых и своих мест.',
                      onTap: () => Navigator.of(context).pop(
                        PlanPlaceAddSource.myPlaces,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SourceCard(
                      icon: Icons.add_location_alt_outlined,
                      title: 'Добавить своё место',
                      subtitle:
                          'Создать новое место и сразу попытаться добавить его в этот план.',
                      onTap: () => Navigator.of(context).pop(
                        PlanPlaceAddSource.createOwnPlace,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color:
                          theme.textTheme.bodyMedium?.color?.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
