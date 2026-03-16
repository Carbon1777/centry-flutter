import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/bonus/bonus_repository_impl.dart';
import '../../data/bonus/bonus_summary_dto.dart';

class CentryMarketScreen extends StatefulWidget {
  final String userId;

  const CentryMarketScreen({super.key, required this.userId});

  @override
  State<CentryMarketScreen> createState() => _CentryMarketScreenState();
}

class _CentryMarketScreenState extends State<CentryMarketScreen> {
  late Future<BonusSummaryDto?> _summaryFuture;
  final _repo = BonusRepositoryImpl(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _summaryFuture = _repo
        .getSummary(appUserId: widget.userId)
        .then<BonusSummaryDto?>((s) => s)
        .catchError((_) => null);
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
            child: FutureBuilder<BonusSummaryDto?>(
              future: _summaryFuture,
              builder: (context, snapshot) {
                final balance = snapshot.data?.currentBalance;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outline, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.monetization_on_outlined,
                          size: 18, color: colors.onSurface),
                      const SizedBox(width: 6),
                      Text(
                        balance != null ? 'Tokens  $balance' : 'Tokens  —',
                        style:
                            text.bodyMedium?.copyWith(color: colors.onSurface),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CentryMarket',
                  style: text.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Откроется с релизом проекта.\n'
                  'На этапе бета-тестирования недоступен.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Токены можно получать и копить уже сейчас —\n'
                  'они сохранятся и будут доступны после открытия.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.5),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
