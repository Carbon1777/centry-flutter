import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/legal/legal_repository_impl.dart';
import '../auth/onboarding_state.dart';
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

  late final LegalRepositoryImpl _repo;

  String get _value => _controller.text.trim();
  int get _length => _value.length;
  bool get _nicknameValid => _length >= 2 && _length <= 20;
  bool get _canSubmit => _nicknameValid && !_loading;

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
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;

      // Шаг 1: создаём app_users (USER если есть auth.uid(), иначе GUEST).
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
      if (state != 'GUEST' && state != 'USER') {
        throw StateError('Unexpected state from bootstrap_guest: $payload');
      }

      // Шаг 2: фиксируем принятие соглашений (версии собраны на AgreementScreen).
      final docs = OnboardingFlowState.instance.acceptedLegalDocuments;
      String? versionByType(String type) {
        try {
          return docs.firstWhere((d) => d.documentType == type).version;
        } catch (_) {
          return null;
        }
      }

      final terms = versionByType('TERMS');
      final privacy = versionByType('PRIVACY');
      final bonusRules = versionByType('BONUS_RULES');
      final childSafety = versionByType('CHILD_SAFETY');

      if (terms != null && privacy != null && bonusRules != null) {
        await _repo.acceptDocuments(
          appUserId:          userId,
          termsVersion:       terms,
          privacyVersion:     privacy,
          bonusRulesVersion:  bonusRules,
          childSafetyVersion: childSafety,
          appVersion:         _kAppVersion,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final error = _errorText ?? _lengthError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Никнейм'),
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
                      const SizedBox(height: 16),
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
