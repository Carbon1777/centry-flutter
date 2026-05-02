// Apple Guideline 1.2 (Safety / UGC) — универсальный bottom-sheet для жалобы на UGC.
// Используется на: чужой профиль, фото, сообщение в чате плана/приватном чате,
// план, место. См. /TZ_apple_ugc_compliance.md разделы 3.1, 3.3, 3.4.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/reports/report_dto.dart';
import '../../data/reports/reports_repository_impl.dart';
import 'center_toast.dart';

class ReportContentSheet {
  ReportContentSheet._();

  /// Открывает sheet «Пожаловаться».
  ///
  /// [targetTypeLabel] — что показать в подзаголовке: «на профиль», «на сообщение» и т.п.
  /// Возвращает `true` при успешной отправке.
  static Future<bool> show(
    BuildContext context, {
    required ReportTargetType targetType,
    required String targetId,
    required String targetTypeLabel,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReportSheet(
        targetType: targetType,
        targetId: targetId,
        targetTypeLabel: targetTypeLabel,
      ),
    );
    return result == true;
  }
}

class _ReportSheet extends StatefulWidget {
  final ReportTargetType targetType;
  final String targetId;
  final String targetTypeLabel;

  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetTypeLabel,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  late final _repo = ReportsRepositoryImpl(Supabase.instance.client);
  final _commentCtrl = TextEditingController();
  ReportCategory? _selected;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cat = _selected;
    if (cat == null || _submitting) return;
    setState(() => _submitting = true);

    final result = await _repo.submit(
      targetType: widget.targetType,
      targetId: widget.targetId,
      category: cat,
      comment: _commentCtrl.text,
    );

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
      await showCenterToast(
        context,
        message: 'Спасибо! Жалоба отправлена. Мы рассмотрим её в течение 24 часов.',
      );
      return;
    }

    setState(() => _submitting = false);
    final msg = switch (result.error) {
      ReportSubmitError.rateLimited =>
        'Слишком много жалоб подряд. Попробуйте через час.',
      ReportSubmitError.selfReport =>
        'Нельзя пожаловаться на собственный контент.',
      ReportSubmitError.unauthorized =>
        'Войдите в аккаунт, чтобы подать жалобу.',
      ReportSubmitError.network =>
        'Нет связи с сервером. Проверьте интернет.',
      _ => 'Не удалось отправить жалобу. Попробуйте позже.',
    };
    await showCenterToast(context, message: msg, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF14161A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Хендл
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3F4A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Заголовок
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Пожаловаться',
                        style: TextStyle(
                          color: Color(0xFFE6EAF2),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close,
                          color: Color(0xFF8B92A0), size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Подзаголовок
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  widget.targetTypeLabel,
                  style: const TextStyle(
                    color: Color(0xFF8B92A0),
                    fontSize: 13,
                  ),
                ),
              ),
              // Список категорий + комментарий
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    for (final cat in ReportCategory.values)
                      _CategoryTile(
                        category: cat,
                        selected: _selected == cat,
                        onTap: _submitting
                            ? null
                            : () => setState(() => _selected = cat),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextField(
                        controller: _commentCtrl,
                        enabled: !_submitting,
                        maxLines: 3,
                        maxLength: 500,
                        style: const TextStyle(color: Color(0xFFE6EAF2)),
                        decoration: InputDecoration(
                          hintText: 'Комментарий (необязательно)',
                          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                          filled: true,
                          fillColor: const Color(0xFF1C1F26),
                          counterStyle:
                              const TextStyle(color: Color(0xFF6B7280)),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Кнопка отправить
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed:
                          (_selected == null || _submitting) ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F8CFF),
                        disabledBackgroundColor: const Color(0xFF2A2E36),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF6B7280),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    Color(0xFFE6EAF2)),
                              ),
                            )
                          : const Text(
                              'Отправить жалобу',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ReportCategory category;
  final bool selected;
  final VoidCallback? onTap;

  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF1F3559)
                : const Color(0xFF1C1F26),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4F8CFF)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF4F8CFF)
                    : const Color(0xFF6B7280),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.labelRu,
                  style: const TextStyle(
                    color: Color(0xFFE6EAF2),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (category.isCritical)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE74C3C), size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
