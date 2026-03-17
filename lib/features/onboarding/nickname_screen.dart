import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/legal/legal_document_dto.dart';
import '../../data/legal/legal_repository_impl.dart';
import '../legal/legal_document_screen.dart';
import 'permissions_screen.dart';

class NicknameScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> result) onBootstrapped;

  const NicknameScreen({super.key, required this.onBootstrapped});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  static const String _kAppVersion = '1.0.0';

  final _controller = TextEditingController();

  bool _loading = false;
  String? _errorText;

  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  bool _bonusRulesAccepted = false;

  List<LegalDocumentDto> _documents = [];
  bool _docsLoading = true;

  late final LegalRepositoryImpl _repo;

  String get _value => _controller.text.trim();
  int get _length => _value.length;
  bool get _nicknameValid => _length >= 2 && _length <= 20;
  bool get _allAccepted =>
      _termsAccepted && _privacyAccepted && _bonusRulesAccepted;
  bool get _canSubmit => _nicknameValid && _allAccepted && !_loading;

  String? get _lengthError {
    if (_length == 0) return null;
    if (_length < 2) return 'Минимум 2 символа';
    if (_length > 20) return 'Максимум 20 символов';
    return null;
  }

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

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;

      // Шаг 1: создаём пользователя
      final dynamic data = await client.rpc(
        'bootstrap_guest',
        params: {'nickname': _value},
      );

      if (data is! Map) {
        throw StateError('bootstrap_guest must return Map, got: $data');
      }

      final payload = Map<String, dynamic>.from(data);

      final userId = payload['id'] as String?;
      final publicId = payload['public_id'] as String?;
      final state = payload['state'] as String?;

      if (userId == null || userId.isEmpty) {
        throw StateError('RPC payload has no id: $payload');
      }
      if (publicId == null || publicId.isEmpty) {
        throw StateError('RPC payload has no public_id: $payload');
      }
      if (state != 'GUEST') {
        throw StateError('Unexpected state from bootstrap_guest: $payload');
      }

      // Шаг 2: фиксируем принятие соглашений (версии получены из загруженных документов)
      final terms = _docByType('TERMS');
      final privacy = _docByType('PRIVACY');
      final bonusRules = _docByType('BONUS_RULES');

      if (terms != null && privacy != null && bonusRules != null) {
        await _repo.acceptDocuments(
          appUserId:         userId,
          termsVersion:      terms.version,
          privacyVersion:    privacy.version,
          bonusRulesVersion: bonusRules.version,
          appVersion:        _kAppVersion,
        );
      }

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PermissionsScreen(
            bootstrapResult: payload,
            onDone: widget.onBootstrapped,
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        setState(() {
          _errorText = 'Этот никнейм занят, выберите другой';
        });
      } else {
        setState(() {
          _errorText = 'Ошибка сервера';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorText = 'Ошибка: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _buildCheckRow({
    required String label,
    required String docType,
    required bool value,
    required void Function(bool?) onChanged,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return InkWell(
      onTap: () => _openDocument(docType),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: _loading ? null : onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = _errorText ?? _lengthError;

    return Scaffold(
      appBar: AppBar(title: const Text('Никнейм')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Text(
                        'Придумайте никнейм',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Так вас будут видеть другие участники',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _controller,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Никнейм',
                          errorText: error,
                          suffixText: '$_length/20',
                        ),
                        onChanged: (_) => setState(() {
                          _errorText = null;
                        }),
                      ),
                      const SizedBox(height: 32),
                      if (_docsLoading)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Text(
                          'Принять условия использования:',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildCheckRow(
                          label: 'Пользовательское соглашение',
                          docType: 'TERMS',
                          value: _termsAccepted,
                          onChanged: (v) =>
                              setState(() => _termsAccepted = v ?? false),
                        ),
                        _buildCheckRow(
                          label: 'Политика конфиденциальности',
                          docType: 'PRIVACY',
                          value: _privacyAccepted,
                          onChanged: (v) =>
                              setState(() => _privacyAccepted = v ?? false),
                        ),
                        _buildCheckRow(
                          label: 'Правила проекта',
                          docType: 'BONUS_RULES',
                          value: _bonusRulesAccepted,
                          onChanged: (v) =>
                              setState(() => _bonusRulesAccepted = v ?? false),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Далее'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
