import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/bonus/bonus_repository_impl.dart';
import '../../data/bonus/bonus_summary_dto.dart';

// ─── DTOs для правил токенов ──────────────────────────────────────────────────

class _TokenRulesSection {
  final String title;
  final int tokens;
  final String body;

  const _TokenRulesSection({
    required this.title,
    required this.tokens,
    required this.body,
  });

  factory _TokenRulesSection.fromJson(Map<String, dynamic> json) =>
      _TokenRulesSection(
        title: json['title'] as String,
        tokens: json['tokens'] as int,
        body: json['body'] as String,
      );
}

class _TokenRules {
  final String title;
  final String intro;
  final List<_TokenRulesSection> sections;
  final List<String> generalRules;

  const _TokenRules({
    required this.title,
    required this.intro,
    required this.sections,
    required this.generalRules,
  });

  factory _TokenRules.fromJson(Map<String, dynamic> json) => _TokenRules(
        title: json['title'] as String,
        intro: json['intro'] as String,
        sections: (json['sections'] as List<dynamic>)
            .map((e) => _TokenRulesSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        generalRules: (json['general_rules'] as List<dynamic>)
            .map((e) => e as String)
            .toList(),
      );
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class CentryMarketScreen extends StatefulWidget {
  final String userId;

  const CentryMarketScreen({super.key, required this.userId});

  @override
  State<CentryMarketScreen> createState() => _CentryMarketScreenState();
}

class _CentryMarketScreenState extends State<CentryMarketScreen> {
  late Future<BonusSummaryDto?> _summaryFuture;
  late final Future<_TokenRules?> _rulesFuture;
  final _repo = BonusRepositoryImpl(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _summaryFuture = _repo
        .getSummary(appUserId: widget.userId)
        .then<BonusSummaryDto?>((s) => s)
        .catchError((_) => null);
    _rulesFuture = _fetchTokenRules();
  }

  Future<_TokenRules?> _fetchTokenRules() async {
    try {
      final response = await Supabase.instance.client
          .from('app_static_content')
          .select('payload')
          .eq('key', 'token_rules')
          .maybeSingle();

      if (response == null) return null;
      return _TokenRules.fromJson(response['payload'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _openTokensRules(BuildContext context, _TokenRules? rules) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: colors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: rules == null
            ? _buildFallbackDialog(text, colors)
            : _buildRulesDialog(rules, text, colors),
      ),
    );
  }

  Widget _buildFallbackDialog(TextTheme text, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Правила начисления Tokens', style: text.titleLarge),
          const SizedBox(height: 12),
          Text(
            'Не удалось загрузить правила. Попробуйте позже.',
            style: text.bodyMedium
                ?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesDialog(
      _TokenRules rules, TextTheme text, ColorScheme colors) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 16, 0),
            child: Row(
              children: [
                Icon(Icons.toll_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rules.title,
                    style:
                        text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close,
                      size: 20,
                      color: colors.onSurface.withValues(alpha: 0.5)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),
          Divider(
            color: colors.outline.withValues(alpha: 0.3),
            height: 1,
          ),

          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rules.intro,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.75),
                      height: 1.5,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    'Начисление токенов',
                    style: text.labelLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.5),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),

                  ...rules.sections.map((s) => _SectionCard(section: s)),

                  const SizedBox(height: 20),

                  Text(
                    'Общие правила',
                    style: text.labelLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.5),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Container(
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    child: Column(
                      children: rules.generalRules
                          .map((rule) => _GeneralRuleRow(rule: rule))
                          .toList(),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
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
          // Баланс токенов
          Padding(
            padding: const EdgeInsets.only(right: 4),
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
                        style: text.bodyMedium
                            ?.copyWith(color: colors.onSurface),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Кнопка правил токенов — под баром
          FutureBuilder<_TokenRules?>(
            future: _rulesFuture,
            builder: (context, snapshot) {
              final ready = snapshot.connectionState == ConnectionState.done;
              return Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: ready
                      ? () => _openTokensRules(context, snapshot.data)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!ready)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: colors.primary,
                            ),
                          )
                        else
                          Icon(Icons.info_outline,
                              size: 16, color: colors.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Tokens · правила',
                          style:
                              text.bodySmall?.copyWith(color: colors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
          Expanded(
            child: Align(
              alignment: const Alignment(0, -0.35),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: colors.outline.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          size: 56,
                          color: colors.onSurface.withValues(alpha: 0.25),
                        ),
                      ),
                      const SizedBox(height: 28),
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
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_run,
                              size: 22,
                              color: colors.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(width: 8),
                          Icon(Icons.directions_run,
                              size: 22,
                              color: colors.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(width: 8),
                          Icon(Icons.directions_run,
                              size: 22,
                              color: colors.onSurface.withValues(alpha: 0.2)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Section card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final _TokenRulesSection section;

  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+${section.tokens}',
              style: text.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style:
                      text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  section.body,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.65),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── General rule row ─────────────────────────────────────────────────────────

class _GeneralRuleRow extends StatelessWidget {
  final String rule;

  const _GeneralRuleRow({required this.rule});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rule,
              style: text.bodySmall?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.65),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
