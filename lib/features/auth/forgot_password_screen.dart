import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

enum _Step { enterEmail, enterCode, enterNewPassword, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AuthService _auth;

  _Step _step = _Step.enterEmail;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  int _resendCooldown = 0;
  Timer? _timer;

  bool get _validEmail {
    final v = _emailCtrl.text.trim();
    return v.contains('@') && v.contains('.');
  }

  @override
  void initState() {
    super.initState();
    _auth = AuthService(Supabase.instance.client);
    final initial = widget.initialEmail?.trim() ?? '';
    if (initial.isNotEmpty) {
      _emailCtrl.text = initial;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    if (!_validEmail || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.requestPasswordReset(email: _emailCtrl.text.trim());
      _startCooldown();
      if (mounted) setState(() => _step = _Step.enterCode);
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось отправить код');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 8 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyRecoveryOtp(
        email: _emailCtrl.text.trim(),
        token: code,
      );
      if (mounted) setState(() => _step = _Step.enterNewPassword);
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ошибка проверки кода');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setNewPassword() async {
    if (_passwordCtrl.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.updatePassword(_passwordCtrl.text);
      // Сессия после updatePassword остаётся активной — выходим, чтобы юзер
      // вошёл с новым паролем штатным flow.
      await _auth.signOut();
      if (mounted) setState(() => _step = _Step.success);
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось обновить пароль');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сброс пароля')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: switch (_step) {
            _Step.enterEmail => _buildEnterEmail(),
            _Step.enterCode => _buildEnterCode(),
            _Step.enterNewPassword => _buildEnterPassword(),
            _Step.success => _buildSuccess(),
          },
        ),
      ),
    );
  }

  Widget _buildEnterEmail() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Сброс пароля',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Введите email — мы пришлём код для сброса пароля.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'example@mail.com',
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_validEmail && !_busy) ? _sendCode : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Отправить код'),
          ),
        ),
      ],
    );
  }

  Widget _buildEnterCode() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Введите код',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Мы отправили 8-значный код на ${_emailCtrl.text.trim()}.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineMedium?.copyWith(
            letterSpacing: 6,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '••••••••',
          ),
          onChanged: (v) {
            setState(() => _error = null);
            if (v.length == 8) _verifyCode();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_codeCtrl.text.length == 8 && !_busy) ? _verifyCode : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Подтвердить'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: (_resendCooldown > 0 || _busy) ? null : _sendCode,
            child: Text(
              _resendCooldown > 0
                  ? 'Отправить код ещё раз ($_resendCooldown)'
                  : 'Отправить код ещё раз',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEnterPassword() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Новый пароль',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Введите новый пароль для входа в аккаунт.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Пароль',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.error)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed:
                (_passwordCtrl.text.isNotEmpty && !_busy) ? _setNewPassword : null,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить пароль'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Готово',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Пароль обновлён. Теперь войдите с новым паролем.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.6),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Вернуться к входу'),
          ),
        ),
      ],
    );
  }
}
