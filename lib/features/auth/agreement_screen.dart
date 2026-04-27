import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/legal/legal_document_dto.dart';
import '../../data/legal/legal_repository_impl.dart';
import '../legal/legal_document_screen.dart';
import 'auth_screen.dart';
import 'onboarding_state.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key, required this.onCompleted});

  final void Function(Map<String, dynamic> result) onCompleted;

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  late final LegalRepositoryImpl _repo;

  bool _accepted = false;
  bool _docsLoading = true;
  List<LegalDocumentDto> _documents = const [];

  @override
  void initState() {
    super.initState();
    _repo = LegalRepositoryImpl(Supabase.instance.client);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final docs = await _repo.getCurrentDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _docsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _docsLoading = false);
    }
  }

  LegalDocumentDto? _docByType(String type) {
    try {
      return _documents.firstWhere((d) => d.documentType == type);
    } catch (_) {
      return null;
    }
  }

  void _openDocument(String type) {
    final doc = _docByType(type);
    if (doc == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LegalDocumentScreen(document: doc)),
    );
  }

  void _continue() {
    if (!_accepted || _docsLoading) return;
    OnboardingFlowState.instance.acceptedLegalDocuments = _documents;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthScreen(onCompleted: widget.onCompleted),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Соглашения'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        'Добро пожаловать',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Перед стартом — пара коротких документов. Загляните, если интересно, и поставьте галку, если со всем согласны.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.6),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_docsLoading)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        )
                      else
                        _buildLegalConsent(),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: (_accepted && !_docsLoading) ? _continue : null,
                  child: const Text('Далее'),
                ),
              ),
            ],
          ),
        ),
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
      spans.add(TextSpan(
        text: link.label,
        style: linkStyle,
        recognizer: TapGestureRecognizer()
          ..onTap = () => _openDocument(link.docType),
      ));
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
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: RichText(text: TextSpan(children: spans)),
          ),
        ),
      ],
    );
  }
}

class _DocLink {
  final String label;
  final String docType;
  const _DocLink(this.label, this.docType);
}
