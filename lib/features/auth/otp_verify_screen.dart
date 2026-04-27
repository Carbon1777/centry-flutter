import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({
    super.key,
    required this.email,
    required this.onVerified,
  });

  final String email;

  /// Вызывается ПОСЛЕ успешной verifyOtp. Caller сам решает, что делать
  /// дальше — push следующего экрана, закрыть модалку, и т.д.
  final Future<void> Function(BuildContext context) onVerified;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _ctrl = TextEditingController();
  late final AuthService _auth;

  bool _busy = false;
  String? _error;
  int _resendCooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _auth = AuthService(Supabase.instance.client);
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
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

  Future<void> _verify() async {
    final code = _ctrl.text.trim();
    if (code.length != 8 || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _auth.verifySignupOtp(email: widget.email, token: code);
      if (!mounted) return;
      await widget.onVerified(context);
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Ошибка проверки кода');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.resendSignupOtp(email: widget.email);
      _startCooldown();
    } on AuthFlowException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось отправить код');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Подтверждение')),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
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
                'Мы отправили 8-значный код на ${widget.email}. Если письма нет — загляните в папку «Спам».',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 8,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
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
                  if (v.length == 8) _verify();
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      (_ctrl.text.length == 8 && !_busy) ? _verify : null,
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
                  onPressed: (_resendCooldown > 0 || _busy) ? null : _resend,
                  child: Text(
                    _resendCooldown > 0
                        ? 'Отправить код ещё раз ($_resendCooldown)'
                        : 'Отправить код ещё раз',
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
