import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Инвайт: генерация через RPC (callback).
///
/// Канон (dev):
/// - Нажали "Сгенерировать инвайт" -> onCreateInvite()
/// - Сервер пока может вернуть:
///   a) token (hex)
///   b) уже готовую строку (например centry://plan-invite?token=...)
/// - UI показывает поле со строкой для шаринга + две кнопки:
///   "Скопировать" и "Поделиться" (системная панель).
///
/// Важно:
/// - Копируем/шарим именно "shareText" (а не голый token),
///   чтобы это было похоже на реальный UX.
/// - Для кликабельности в почте/мессенджерах, в будущем заменишь baseUrl
///   на реально работающий https-домен (Vercel/GitHub Pages и т.д.)
class PlanInviteModal extends StatefulWidget {
  final Future<String> Function() onCreateInvite;

  const PlanInviteModal({
    super.key,
    required this.onCreateInvite,
  });

  @override
  State<PlanInviteModal> createState() => _PlanInviteModalState();
}

class _PlanInviteModalState extends State<PlanInviteModal> {
  bool _loading = false;
  String? _shareText;
  String? _error;

  // ✅ Канон: кликабельная https-ссылка на реальный домен, который привязан App Links.
  static const String _httpsBaseUrl = 'https://www.centry.website/plan-invite';

  /// Нормализуем ответ сервера:
  /// - если уже есть "://", считаем это готовой ссылкой/строкой
  /// - иначе считаем, что это token и строим shareText
  String _normalizeToShareText(String serverValue) {
    final v = serverValue.trim();
    if (v.isEmpty) return v;

    // Уже готовая ссылка/строка (сервер может вернуть share_url / share_text)
    if (v.contains('://')) return v;

    // Иначе считаем, что это token и строим каноничный https share-url.
    return '$_httpsBaseUrl?token=$v';
  }

  Future<void> _generate() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _shareText = null;
    });

    try {
      final raw = await widget.onCreateInvite();
      final text = _normalizeToShareText(raw);

      if (!mounted) return;
      setState(() => _shareText = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _copyShareText() async {
    final t = _shareText;
    if (t == null || t.isEmpty) return;

    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано')),
    );
  }

  Future<void> _shareInvite() async {
    final t = _shareText;
    if (t == null || t.isEmpty) return;

    await Share.share(t);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.75;
    final hasInvite = _shareText != null && _shareText!.trim().isNotEmpty;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Инвайт',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // До генерации — одна кнопка
                      if (!hasInvite) ...[
                        OutlinedButton(
                          onPressed: _loading ? null : _generate,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _loading ? 'Генерируем…' : 'Сгенерировать инвайт',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],

                      // После генерации — поле + 2 кнопки
                      if (hasInvite) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Инвайт:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: SelectableText(_shareText!),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _copyShareText,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Скопировать'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _shareInvite,
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Поделиться'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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
