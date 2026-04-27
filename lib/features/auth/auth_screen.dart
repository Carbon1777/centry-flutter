import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../onboarding/nickname_screen.dart';
import 'auth_service.dart';
import 'forgot_password_screen.dart';
import 'onboarding_state.dart';
import 'otp_verify_screen.dart';

enum _AuthMode { signUp, signIn }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onCompleted});

  final void Function(Map<String, dynamic> result) onCompleted;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AuthService _auth;

  _AuthMode _mode = _AuthMode.signUp;
  bool _busy = false;
  String? _error;
  bool _obscure = true;
  bool _emailTaken = false;

  bool get _validEmail {
    final v = _emailCtrl.text.trim();
    return v.contains('@') && v.contains('.');
  }

  bool get _validPassword => _passwordCtrl.text.isNotEmpty;

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
      _emailTaken = false;
    });

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      if (_mode == _AuthMode.signUp) {
        // Pre-check: если email уже занят — Supabase молча вернёт 200 OK
        // на signUp, но письмо НЕ отправит (privacy guard). Спросим заранее
        // и подскажем юзеру, что нужно войти / восстановить пароль.
        final available = await _auth.checkEmailAvailable(email);
        if (!mounted) return;
        if (!available) {
          setState(() => _emailTaken = true);
          return;
        }

        await _auth.signUp(email: email, password: password);
        OnboardingFlowState.instance.pendingEmail = email;
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OtpVerifyScreen(
              email: email,
              onVerified: (ctx) async {
                Navigator.of(ctx).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => NicknameScreen(
                      onBootstrapped: widget.onCompleted,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      } else {
        await _auth.signInWithPassword(email: email, password: password);
        OnboardingFlowState.instance.pendingEmail = email;
        if (!mounted) return;
        await _proceedAfterSignIn();
      }
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ошибка сервера');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _switchToSignInWithEmail() {
    setState(() {
      _mode = _AuthMode.signIn;
      _emailTaken = false;
      _error = null;
      _passwordCtrl.clear();
    });
  }

  void _openForgotPasswordWithEmail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          initialEmail: _emailCtrl.text.trim(),
        ),
      ),
    );
  }

  void _skip() {
    // Гостевой режим: не было signUp/signIn, app_users создастся как GUEST.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NicknameScreen(onBootstrapped: widget.onCompleted),
      ),
    );
  }

  /// После успешного signIn у уже-зарегистрированного юзера app_users
  /// существует — забираем профиль через current_user и пропускаем NicknameScreen.
  /// Если current_user пуст (юзер ранее регался magic-link'ом и app_users по
  /// какой-то причине не было) — показываем Nickname как fallback.
  Future<void> _proceedAfterSignIn() async {
    try {
      final dynamic raw =
          await Supabase.instance.client.rpc('current_user');
      if (raw is Map) {
        final payload = Map<String, dynamic>.from(raw);
        final userId = payload['id'] as String?;
        final publicId = payload['public_id'] as String?;
        if (userId != null && userId.isNotEmpty &&
            publicId != null && publicId.isNotEmpty) {
          widget.onCompleted({
            'id': userId,
            'public_id': publicId,
            'nickname': payload['nickname'] ?? '',
            'state': 'USER',
          });
          // BootstrapGate.build уже покажет HomeScreen внизу. Закрываем
          // все pushed-экраны (AuthScreen и предки), иначе пользователь
          // остаётся на форме входа.
          if (mounted) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
          return;
        }
      }
    } catch (_) {
      // network glitch — попадём в fallback ниже
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => NicknameScreen(onBootstrapped: widget.onCompleted),
      ),
    );
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _AuthMode.signUp ? _AuthMode.signIn : _AuthMode.signUp;
      _error = null;
    });
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isSignUp = _mode == _AuthMode.signUp;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSignUp ? 'Регистрация' : 'Вход'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Text(
                  isSignUp ? 'Создайте аккаунт' : 'С возвращением',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isSignUp
                      ? 'Email и пароль нужны, чтобы вы могли вернуться в аккаунт после переустановки приложения.'
                      : 'Введите email и пароль от вашего аккаунта.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface.withValues(alpha: 0.6),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'example@mail.com',
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                    _emailTaken = false;
                  }),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Пароль',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (!isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : _openForgotPassword,
                      child: const Text('Забыли пароль?'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ],
                if (_emailTaken && isSignUp) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Этот email уже зарегистрирован',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Если это ваш аккаунт — войдите по паролю или восстановите его, если забыли.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.7),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _switchToSignInWithEmail,
                            child: const Text('Войти'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _busy ? null : _openForgotPasswordWithEmail,
                            child: const Text('Восстановить пароль'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isSignUp ? 'Зарегистрироваться' : 'Войти'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _busy ? null : _toggleMode,
                    child: Text(
                      isSignUp
                          ? 'Уже есть аккаунт? Войти'
                          : 'Новый пользователь? Зарегистрироваться',
                    ),
                  ),
                ),
                if (isSignUp) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _busy ? null : _skip,
                      child: const Text(
                        'Пропустить',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
