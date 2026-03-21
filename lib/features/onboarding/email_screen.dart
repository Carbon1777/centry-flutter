import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/user_snapshot_storage.dart';

enum EmailFlowState { initial, sending, confirmSent, emailExists, recoverySent }

class EmailScreen extends StatefulWidget {
  final Map<String, dynamic> bootstrapResult;
  final void Function(Map<String, dynamic> result) onDone;

  const EmailScreen({
    super.key,
    required this.bootstrapResult,
    required this.onDone,
  });

  @override
  State<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends State<EmailScreen> {
  final _controller = TextEditingController();
  late final StreamSubscription<AuthState> _authSub;

  EmailFlowState _state = EmailFlowState.initial;
  String? _error;

  String get _userId {
    final id = widget.bootstrapResult['id'];
    if (id is! String || id.isEmpty) {
      throw StateError(
        'Invalid bootstrap_guest payload (missing id): ${widget.bootstrapResult}',
      );
    }
    return id;
  }

  bool get _validEmail {
    final v = _controller.text.trim();
    return v.contains('@') && v.contains('.');
  }

  @override
  void initState() {
    super.initState();

    final auth = Supabase.instance.client.auth;

    _authSub = auth.onAuthStateChange.listen((data) async {
      if (data.session != null && mounted) {
        try {
          await UserSnapshotStorage().save(
            UserSnapshot(
              id: _userId,
              publicId: widget.bootstrapResult['public_id'] as String,
              nickname: widget.bootstrapResult['nickname'] as String,
              state: 'USER',
            ),
          );

          widget.onDone({
            ...widget.bootstrapResult,
            'state': 'USER',
          });

          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _error = 'Ошибка обновления профиля';
            _state = EmailFlowState.initial;
          });
        }
      }
    });

    if (auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        try {
          await UserSnapshotStorage().save(
            UserSnapshot(
              id: _userId,
              publicId: widget.bootstrapResult['public_id'] as String,
              nickname: widget.bootstrapResult['nickname'] as String,
              state: 'USER',
            ),
          );

          widget.onDone({
            ...widget.bootstrapResult,
            'state': 'USER',
          });

          if (!mounted) return;
          Navigator.of(context).popUntil((route) => route.isFirst);
        } catch (_) {}
      });
    }
  }

  void _finishOnboardingSkip() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onDone(widget.bootstrapResult);
  }

  Future<void> _submit() async {
    if (!_validEmail || _state == EmailFlowState.sending) return;

    setState(() {
      _state = EmailFlowState.sending;
      _error = null;
    });

    final client = Supabase.instance.client;
    final email = _controller.text.trim();

    try {
      final available = await client
          .rpc('check_email_available', params: {'p_email': email}) as bool;

      if (available) {
        await client.rpc(
          'set_email_pending',
          params: {
            'p_user_id': _userId,
            'p_email': email,
          },
        );

        await client.auth.signInWithOtp(
          email: email,
          emailRedirectTo: 'centry://auth',
        );

        setState(() {
          _state = EmailFlowState.confirmSent;
        });
      } else {
        setState(() {
          _state = EmailFlowState.emailExists;
        });
      }
    } catch (e) {
      setState(() {
        _state = EmailFlowState.initial;
        _error = 'Ошибка сервера';
      });
    }
  }

  Future<void> _recover() async {
    if (_state == EmailFlowState.sending) return;

    setState(() {
      _state = EmailFlowState.sending;
      _error = null;
    });

    final email = _controller.text.trim();

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: 'centry://auth',
      );

      setState(() {
        _state = EmailFlowState.recoverySent;
      });
    } catch (_) {
      setState(() {
        _state = EmailFlowState.emailExists;
        _error = 'Не удалось отправить письмо восстановления';
      });
    }
  }

  void _resetEmail() {
    setState(() {
      _controller.clear();
      _state = EmailFlowState.initial;
      _error = null;
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final showInput = _state == EmailFlowState.initial ||
        _state == EmailFlowState.emailExists;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Почта'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.08),
                if (showInput) ...[
                  Text(
                    'Укажите почту',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Это позволит расширить функциональность и быстро восстановить доступ после переустановки приложения.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'example@mail.com',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                if (_state == EmailFlowState.emailExists) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Эта почта уже зарегистрирована. Восстановите доступ.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ],
                if (_state == EmailFlowState.confirmSent) ...[
                  Text(
                    'Письмо отправлено',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Проверьте почту и перейдите по ссылке из письма. Если не нашли — загляните в папку «Спам».',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: _resetEmail,
                    child: Text(
                      'Ошиблись в адресе? Ввести другой',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
                if (_state == EmailFlowState.recoverySent) ...[
                  Text(
                    'Письмо отправлено',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Проверьте почту и перейдите по ссылке для восстановления доступа.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      height: 1.45,
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
                const SizedBox(height: 32),
                if (_state == EmailFlowState.initial ||
                    _state == EmailFlowState.emailExists) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_state == EmailFlowState.initial)
                          ? ((!_validEmail || _state == EmailFlowState.sending)
                              ? null
                              : _submit)
                          : (_state == EmailFlowState.sending ? null : _recover),
                      child: _state == EmailFlowState.sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _state == EmailFlowState.initial
                                  ? 'Подтвердить'
                                  : 'Восстановить',
                            ),
                    ),
                  ),
                  if (_state == EmailFlowState.initial) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _finishOnboardingSkip,
                        child: const Text(
                          'Пропустить',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
