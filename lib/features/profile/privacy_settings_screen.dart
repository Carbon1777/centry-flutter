import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'delete_account_modal.dart';
import 'app_version_label.dart';
import '../../ui/support/support_direction_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  Map<String, bool>? _settings;
  bool _loading = true;
  String? _error;

  // контексты и поля новой модели
  static const _contexts = ['in_plans', 'in_feed'];
  static const _contextLabels = ['В планах', 'В ленте'];

  static const _miniFields = ['mini_profile'];
  static const _miniFieldLabels = ['Видят'];

  static const _fullFields = ['full_profile'];
  static const _fullFieldLabels = ['Видят'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Supabase.instance.client.rpc('get_privacy_settings');
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

  bool _get(String ctx, String field) => _settings?['$ctx.$field'] ?? true;

  Future<void> _openSupport() async {
    try {
      const storage = FlutterSecureStorage();
      final raw = await storage.read(key: 'user_snapshot');
      String? appUserId;
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        appUserId = j['id']?.toString();
      }
      if (appUserId == null || appUserId.isEmpty) {
        final authUid = Supabase.instance.client.auth.currentUser?.id;
        if (authUid == null) return;
        final row = await Supabase.instance.client
            .from('app_users')
            .select('id')
            .eq('auth_user_id', authUid)
            .maybeSingle();
        appUserId = row?['id']?.toString();
      }
      if (!mounted || appUserId == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportDirectionScreen(appUserId: appUserId!),
        ),
      );
    } catch (e) {
      debugPrint('[PrivacySettings] openSupport error: $e');
    }
  }

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
      appBar: AppBar(title: const Text('Настройки')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Ошибка: $_error'))
              : _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    const hPadding = 16.0;
    const fieldColW = 90.0;
    final screenW = MediaQuery.of(context).size.width;
    final ctxColW = (screenW - hPadding * 2 - fieldColW) / 2;

    final columnWidths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(fieldColW),
      1: FixedColumnWidth(ctxColW),
      2: FixedColumnWidth(ctxColW),
    };

    final headerRow = TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      children: [
        const SizedBox(height: 36),
        ..._contextLabels.map(
          (label) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Где видны мои профили', style: text.titleMedium),
                const SizedBox(height: 14),

                // ── Мини профиль ──
                Text(
                  'Мини профиль',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Table(
                  columnWidths: columnWidths,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    headerRow,
                    ..._buildRows(_miniFields, _miniFieldLabels, text, colors),
                  ],
                ),

                const SizedBox(height: 16),

                // ── Полный профиль ──
                Text(
                  'Полный профиль',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.outline,
                  ),
                ),
                const SizedBox(height: 6),
                Table(
                  columnWidths: columnWidths,
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    headerRow,
                    ..._buildRows(_fullFields, _fullFieldLabels, text, colors),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Пометка про друзей ──
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '* Настройки приватности не распространяются на ваших друзей — для них мини профиль и полный профиль всегда открыты.',
                    style: text.bodySmall?.copyWith(color: colors.outline, fontSize: 12),
                  ),
                ),

                const Spacer(),

                // ── Контакты + версия + удаление ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mail_outline, size: 13, color: colors.outline.withValues(alpha: 0.6)),
                              const SizedBox(width: 5),
                              Text('support@centryweb.ru', style: TextStyle(fontSize: 12, color: colors.outline.withValues(alpha: 0.7))),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mail_outline, size: 13, color: colors.outline.withValues(alpha: 0.6)),
                              const SizedBox(width: 5),
                              Text('partners@centryweb.ru', style: TextStyle(fontSize: 12, color: colors.outline.withValues(alpha: 0.7))),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mail_outline, size: 13, color: colors.outline.withValues(alpha: 0.6)),
                              const SizedBox(width: 5),
                              Text('privacy@centryweb.ru', style: TextStyle(fontSize: 12, color: colors.outline.withValues(alpha: 0.7))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.language, size: 13, color: colors.outline.withValues(alpha: 0.6)),
                          const SizedBox(width: 5),
                          Text('centryweb.ru', style: TextStyle(fontSize: 12, color: colors.outline.withValues(alpha: 0.7))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const AppVersionLabel(),
                      const SizedBox(height: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => showDialog<void>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => DeleteAccountModal(onAccountDeleted: () {}),
                        ),
                        child: Text(
                          'Удалить аккаунт',
                          style: text.bodySmall?.copyWith(
                            color: colors.error.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          // Иконка поддержки — правый верхний угол контента
          Positioned(
            top: 4,
            right: 12,
            child: _SupportButton(onTap: _openSupport),
          ),
        ],
      ),
    );
  }

  List<TableRow> _buildRows(
    List<String> fields,
    List<String> labels,
    TextTheme text,
    ColorScheme colors,
  ) {
    return List.generate(fields.length, (fi) {
      final field = fields[fi];
      final label = labels[fi];

      return TableRow(
        decoration: fi < fields.length - 1
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              )
            : null,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(label, style: text.bodyMedium),
          ),
          ..._contexts.map((ctx) {
            final val = _get(ctx, field);
            return Center(
              child: _EyeSwitch(
                value: val,
                onChanged: (v) => _toggle(ctx, field, v),
              ),
            );
          }),
        ],
      );
    });
  }
}

// =======================
// Eye switch
// =======================

class _EyeSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _EyeSwitch({required this.value, required this.onChanged});

  static const double _trackW = 62;
  static const double _trackH = 32;
  static const double _thumbW = 32;
  static const double _thumbH = 26;
  static const double _thumbPadH = 2;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const dur = Duration(milliseconds: 200);

    const thumbOff = _thumbPadH;
    const thumbOn = _trackW - _thumbW - _thumbPadH;

    // Иконка — в центре свободной части трека (противоположной стороне от ползунка)
    const freeW = _trackW - _thumbW - _thumbPadH * 2;
    final iconLeft = value
        ? _thumbPadH + (freeW - _iconSize) / 2
        : _thumbW + _thumbPadH + (freeW - _iconSize) / 2;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: dur,
        width: _trackW,
        height: _trackH,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_trackH / 2),
          color: value ? colors.primary : colors.surfaceContainerHighest,
          border: Border.all(
            color: value
                ? colors.primary
                : colors.outline.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Иконка глаза
            AnimatedPositioned(
              duration: dur,
              curve: Curves.easeInOut,
              left: iconLeft,
              top: (_trackH - _iconSize) / 2,
              child: Icon(
                value ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: _iconSize,
                color: value
                    ? Colors.white.withValues(alpha: 0.85)
                    : colors.onSurface.withValues(alpha: 0.4),
              ),
            ),
            // Ползунок (вытянутый овал)
            AnimatedPositioned(
              duration: dur,
              curve: Curves.easeInOut,
              left: value ? thumbOn : thumbOff,
              top: (_trackH - _thumbH) / 2,
              child: Container(
                width: _thumbW,
                height: _thumbH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_thumbH / 2),
                  color: Colors.white,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// Delete account footer
// =======================

// =======================
// Кнопка поддержки с эффектом нажатия
// =======================

class _SupportButton extends StatefulWidget {
  final VoidCallback onTap;

  const _SupportButton({required this.onTap});

  @override
  State<_SupportButton> createState() => _SupportButtonState();
}

class _SupportButtonState extends State<_SupportButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) => _ctrl.forward();
  void _onTapUp(TapUpDetails _) {
    _ctrl.reverse();
    widget.onTap();
  }

  void _onTapCancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(
        scale: _scale,
        child: Image.asset(
          'assets/images/support.png',
          width: 84,
          height: 84,
        ),
      ),
    );
  }
}

// =======================
// Delete account footer
// =======================


