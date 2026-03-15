import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  Map<String, bool>? _settings;
  bool _loading = true;
  String? _error;

  static const _contexts = ['all', 'friends', 'in_plans', 'in_feed'];
  static const _contextLabels = ['Все', 'Друзья', 'В планах', 'В ленте'];

  static const _fields = ['nickname', 'avatar', 'name', 'gender', 'age'];
  static const _fieldLabels = ['Никнейм', 'Аватар', 'Имя', 'Пол', 'Возраст'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res =
          await Supabase.instance.client.rpc('get_privacy_settings');
      final map = (res as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as bool),
      );
      setState(() {
        _settings = map;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _get(String ctx, String field) =>
      _settings?['$ctx.$field'] ?? true;

  Future<void> _toggle(String ctx, String field, bool value) async {
    final key = '$ctx.$field';
    setState(() => _settings![key] = value);

    try {
      await Supabase.instance.client.rpc('set_privacy_setting', params: {
        'p_context': ctx,
        'p_field': field,
        'p_visible': value,
      });
    } catch (e) {
      setState(() => _settings![key] = !value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки приватности')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : _buildTable(context),
    );
  }

  Widget _buildTable(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    // Ширина колонок — динамически под экран
    const hPadding = 10.0;
    const fieldColW = 80.0;
    final screenW = MediaQuery.of(context).size.width;
    final ctxColW = (screenW - hPadding * 2 - fieldColW) / 4;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Кто видит мои данные', style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Если поле открыто для всех — отдельные настройки по друзьям, планам и ленте не нужны',
            style: text.bodySmall?.copyWith(color: colors.outline),
          ),
          const SizedBox(height: 20),

          // Таблица
          Table(
            columnWidths: {
              0: FixedColumnWidth(fieldColW),
              1: FixedColumnWidth(ctxColW),
              2: FixedColumnWidth(ctxColW),
              3: FixedColumnWidth(ctxColW),
              4: FixedColumnWidth(ctxColW),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              // Header row
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                children: [
                  const SizedBox(height: 36),
                  ..._contextLabels.map(
                    (label) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Data rows
              ...List.generate(_fields.length, (fi) {
                final field = _fields[fi];
                final fieldLabel = _fieldLabels[fi];
                final allOn = _get('all', field);

                return TableRow(
                  decoration: fi < _fields.length - 1
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                                color: colors.outlineVariant.withValues(alpha: 0.5)),
                          ),
                        )
                      : null,
                  children: [
                    // Field label
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(fieldLabel, style: text.bodyMedium),
                    ),

                    // Context toggles
                    ...List.generate(_contexts.length, (ci) {
                      final ctx = _contexts[ci];
                      final isAllColumn = ctx == 'all';
                      final val = _get(ctx, field);

                      // Остальные колонки неактивны если "Все" = true
                      final disabled = !isAllColumn && allOn;

                      return _TableCell(
                        value: disabled ? true : val,
                        disabled: disabled,
                        onChanged: disabled
                            ? null
                            : (v) => _toggle(ctx, field, v),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// =======================
// Cell widget
// =======================

class _TableCell extends StatelessWidget {
  final bool value;
  final bool disabled;
  final ValueChanged<bool>? onChanged;

  const _TableCell({
    required this.value,
    required this.disabled,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Transform.scale(
        scale: 0.88,
        child: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: disabled ? colors.outline : colors.primary,
          trackColor: disabled
              ? WidgetStateProperty.all(
                  colors.surfaceContainerHighest,
                )
              : null,
          thumbColor: disabled
              ? WidgetStateProperty.all(colors.outline)
              : null,
        ),
      ),
    );
  }
}
