import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/legal/legal_document_dto.dart';
import '../../data/legal/legal_repository_impl.dart';
import '../../ui/common/center_toast.dart';
import 'legal_document_screen.dart';

class LegalAgreementScreen extends StatefulWidget {
  final String appUserId;
  final Map<String, dynamic> bootstrapResult;
  final void Function(Map<String, dynamic> result) onAccepted;

  const LegalAgreementScreen({
    super.key,
    required this.appUserId,
    required this.bootstrapResult,
    required this.onAccepted,
  });

  @override
  State<LegalAgreementScreen> createState() => _LegalAgreementScreenState();
}

class _LegalAgreementScreenState extends State<LegalAgreementScreen> {
  static const String _kAppVersion = '1.0.0';

  bool _allAccepted = false;

  bool _loading = false;
  bool _docsLoading = true;
  String? _docsError;

  List<LegalDocumentDto> _documents = [];

  late final LegalRepositoryImpl _repo;

  @override
  void initState() {
    super.initState();
    _repo = LegalRepositoryImpl(Supabase.instance.client);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _docsLoading = true;
      _docsError = null;
    });
    try {
      final docs = await _repo.getCurrentDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _docsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _docsError = 'Не удалось загрузить документы';
        _docsLoading = false;
      });
    }
  }

  LegalDocumentDto? _docByType(String type) {
    try {
      return _documents.firstWhere((d) => d.documentType == type);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onContinue() async {
    if (!_allAccepted) {
      showCenterToast(context, message: 'Примите все условия для продолжения');
      return;
    }

    final terms = _docByType('TERMS');
    final privacy = _docByType('PRIVACY');
    final bonusRules = _docByType('BONUS_RULES');
    final childSafety = _docByType('CHILD_SAFETY');

    if (terms == null || privacy == null || bonusRules == null) {
      showCenterToast(context, message: 'Ошибка: документы не загружены');
      return;
    }

    setState(() => _loading = true);

    try {
      await _repo.acceptDocuments(
        appUserId:          widget.appUserId,
        termsVersion:       terms.version,
        privacyVersion:     privacy.version,
        bonusRulesVersion:  bonusRules.version,
        childSafetyVersion: childSafety?.version,
        appVersion:         _kAppVersion,
      );

      if (!mounted) return;
      widget.onAccepted(widget.bootstrapResult);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showCenterToast(context, message: 'Ошибка сервера. Попробуйте ещё раз');
    }
  }

  void _openDocument(String type) {
    final doc = _docByType(type);
    if (doc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(document: doc),
      ),
    );
  }

  Widget _buildLegalConsent() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final linkStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary,
    );
    final normalStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurface.withValues(alpha: 0.8),
    );

    final docLinks = <_DocLink>[
      const _DocLink('Условиями использования', 'TERMS'),
      const _DocLink('Политикой конфиденциальности', 'PRIVACY'),
      const _DocLink('Правилами сообщества', 'BONUS_RULES'),
      const _DocLink('Стандартами безопасности детей', 'CHILD_SAFETY'),
    ];

    final spans = <InlineSpan>[
      TextSpan(text: 'Я согласен с ', style: normalStyle),
    ];

    for (var i = 0; i < docLinks.length; i++) {
      final link = docLinks[i];
      spans.add(
        TextSpan(
          text: link.label,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openDocument(link.docType),
        ),
      );

      if (i < docLinks.length - 2) {
        spans.add(TextSpan(text: ', ', style: normalStyle));
      } else if (i == docLinks.length - 2) {
        spans.add(TextSpan(text: ' и ', style: normalStyle));
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _allAccepted,
          onChanged: _loading
              ? null
              : (v) => setState(() => _allAccepted = v ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: RichText(
              text: TextSpan(children: spans),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Условия использования')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(
                'Для продолжения необходимо принять:',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Нажмите на ссылку, чтобы ознакомиться с документом.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),

              if (_docsLoading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_docsError != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _docsError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _loadDocuments,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                _buildLegalConsent(),
                const Spacer(),
              ],

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_loading || _docsLoading || _docsError != null)
                      ? null
                      : _onContinue,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Продолжить'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocLink {
  final String label;
  final String docType;
  const _DocLink(this.label, this.docType);
}
