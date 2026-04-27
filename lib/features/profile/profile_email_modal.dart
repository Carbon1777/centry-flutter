import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local/user_snapshot_storage.dart';
import '../auth/auth_service.dart';
import '../auth/otp_verify_screen.dart';

/// Модалка для гостя в Profile: email+password регистрация → 6-значный
/// OTP-код → линковка app_users c auth.users через handle_auth_user_created
/// (по email) ИЛИ через finalize_auth_for_guest fallback.
class ProfileEmailModal extends StatefulWidget {
  final Map<String, dynamic> bootstrapResult;
  final VoidCallback? onUpgradeSuccess;

  const ProfileEmailModal({
    super.key,
    required this.bootstrapResult,
    this.onUpgradeSuccess,
  });

  @override
  State<ProfileEmailModal> createState() => _ProfileEmailModalState();
}

class _ProfileEmailModalState extends State<ProfileEmailModal> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AuthService _auth;

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  String get _userId {
    final id = widget.bootstrapResult['id'];
    if (id is! String || id.isEmpty) {
      throw StateError(
        'Invalid bootstrap payload (missing id): ${widget.bootstrapResult}',
      );
    }
    return id;
  }

  bool get _validEmail {
    final v = _emailCtrl.text.trim();
    return v.contains('@') && v.contains('.');
  }

  bool get _validPassword => _passwordCtrl.text.length >= 6;

  bool get _canSubmit => _validEmail && _validPassword && !_busy;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(Supabase.instance.client);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final guestUserId = _userId;
    final publicId = widget.bootstrapResult['public_id'] as String?;
    final nickname = widget.bootstrapResult['nickname'] as String?;

    try {
      // set_email_pending заранее, чтобы триггер handle_auth_user_created
      // нашёл и линковал текущий GUEST app_users по email.
      await Supabase.instance.client.rpc(
        'set_email_pending',
        params: {'p_user_id': guestUserId, 'p_email': email},
      );

      await _auth.signUp(email: email, password: password);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerifyScreen(
            email: email,
            onVerified: (ctx) async {
              await _onVerified(ctx, guestUserId, publicId, nickname);
            },
          ),
        ),
      );
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ошибка сервера');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onVerified(
    BuildContext ctx,
    String guestUserId,
    String? publicId,
    String? nickname,
  ) async {
    try {
      // Safety net: если триггер handle_auth_user_created по какой-то причине
      // не сработал — finalize_auth_for_guest идемпотентно довяжет.
      await Supabase.instance.client.rpc(
        'finalize_auth_for_guest',
        params: {'p_guest_user_id': guestUserId},
      );

      if (publicId != null && nickname != null) {
        await UserSnapshotStorage().save(
          UserSnapshot(
            id: guestUserId,
            publicId: publicId,
            nickname: nickname,
            state: 'USER',
          ),
        );
      }

      if (!ctx.mounted) return;
      // Закрываем OtpVerifyScreen и саму модалку.
      Navigator.of(ctx).pop();
      if (mounted) {
        Navigator.of(context).pop();
        widget.onUpgradeSuccess?.call();
      }
    } catch (_) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Не удалось завершить регистрацию')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final bottomInset = viewInsets.bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + (bottomInset > 0 ? 8 : 0),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Регистрация',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        helperText: 'Минимум 6 символов',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _canSubmit
                                ? colors.primary
                                : Colors.grey.shade700,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _canSubmit ? _submit : null,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Зарегистрироваться'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
