import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/user_snapshot_storage.dart';

enum ProfileEmailFlowState {
  initial,
  sending,
  confirmSent,
  emailExists,
  recoverySent,
}

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
  final _controller = TextEditingController();
  StreamSubscription<AuthState>? _authSub;

  ProfileEmailFlowState _state = ProfileEmailFlowState.initial;
  String? _error;

  bool _upgradeHandled = false;

  String get _userId {
    final id = widget.bootstrapResult['id'];
    if (id is! String || id.isEmpty) {
      debugPrint(
        '[ProfileEmailModal] ❌ Invalid bootstrap payload: ${widget.bootstrapResult}',
      );
      throw StateError(
        'Invalid bootstrap payload (missing id): ${widget.bootstrapResult}',
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

    debugPrint('[ProfileEmailModal] initState');
    debugPrint(
      '[ProfileEmailModal] bootstrapResult: ${widget.bootstrapResult}',
    );

    final auth = Supabase.instance.client.auth;

    Future<void> handleUpgrade(Session session) async {
      debugPrint(
        '[ProfileEmailModal] handleUpgrade START | session.user.id=${session.user.id} | _upgradeHandled=$_upgradeHandled',
      );

      if (_upgradeHandled) {
        debugPrint(
          '[ProfileEmailModal] handleUpgrade ABORT — already handled',
        );
        return;
      }

      _upgradeHandled = true;
      debugPrint('[ProfileEmailModal] handleUpgrade FLAG SET');

      try {        debugPrint('[ProfileEmailModal] Saving snapshot as USER (no DB state check)...');

        await UserSnapshotStorage().save(
          UserSnapshot(
            id: _userId,
            publicId: widget.bootstrapResult['public_id'] as String,
            nickname: widget.bootstrapResult['nickname'] as String,
            state: 'USER',
          ),
        );

        debugPrint('[ProfileEmailModal] Snapshot saved as USER');

        if (!mounted) {
          debugPrint('[ProfileEmailModal] Not mounted — abort pop');
          return;
        }

        debugPrint('[ProfileEmailModal] Navigator.pop() after upgrade');
        if (widget.onUpgradeSuccess != null) {
          debugPrint('[ProfileEmailModal] Calling onUpgradeSuccess callback');
          widget.onUpgradeSuccess!();
        }
        Navigator.of(context).pop();
        return;} catch (e, st) {
        debugPrint(
          '[ProfileEmailModal] ❌ handleUpgrade ERROR: $e',
        );
        debugPrint(
          '[ProfileEmailModal] ❌ handleUpgrade STACKTRACE: $st',
        );

        if (!mounted) {
          debugPrint('[ProfileEmailModal] Not mounted in catch — abort');
          return;
        }

        setState(() {
          _state = ProfileEmailFlowState.initial;
          _error = 'Ошибка обновления профиля';
        });

        debugPrint('[ProfileEmailModal] State reset to initial after error');
      }
    }

    _authSub = auth.onAuthStateChange.listen((data) {
      debugPrint(
        '[ProfileEmailModal] onAuthStateChange | event=${data.event} | session=${data.session?.user.id}',
      );

      if (data.session != null && mounted) {
        handleUpgrade(data.session!);
      }
    });

    if (auth.currentSession != null) {
      debugPrint(
        '[ProfileEmailModal] currentSession exists at init: ${auth.currentSession!.user.id}',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          debugPrint(
            '[ProfileEmailModal] Not mounted in postFrame — abort handleUpgrade',
          );
          return;
        }
        debugPrint(
          '[ProfileEmailModal] postFrame handleUpgrade call',
        );
        handleUpgrade(auth.currentSession!);
      });
    } else {
      debugPrint('[ProfileEmailModal] No currentSession at init');
    }
  }

  @override
  void dispose() {
    debugPrint('[ProfileEmailModal] dispose');
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('[ProfileEmailModal] _submit called');

    if (!_validEmail || _state == ProfileEmailFlowState.sending) {
      debugPrint(
        '[ProfileEmailModal] _submit aborted | valid=$_validEmail | state=$_state',
      );
      return;
    }

    setState(() {
      _state = ProfileEmailFlowState.sending;
      _error = null;
    });

    final client = Supabase.instance.client;
    final email = _controller.text.trim();

    debugPrint('[ProfileEmailModal] Checking email availability: $email');

    try {
      final available = await client.rpc(
        'check_email_available',
        params: {'p_email': email},
      ) as bool;

      debugPrint(
        '[ProfileEmailModal] check_email_available result: $available',
      );

      if (available) {
        debugPrint(
          '[ProfileEmailModal] Setting email pending for user=$_userId',
        );

        await client.rpc(
          'set_email_pending',
          params: {
            'p_user_id': _userId,
            'p_email': email,
          },
        );

        debugPrint(
          '[ProfileEmailModal] Calling signInWithOtp (redirect centry://auth)',
        );

        await client.auth.signInWithOtp(
          email: email,
          emailRedirectTo: 'centry://auth',
        );

        setState(() {
          _state = ProfileEmailFlowState.confirmSent;
        });

        debugPrint('[ProfileEmailModal] OTP sent successfully');
      } else {
        debugPrint(
          '[ProfileEmailModal] Email already exists → switching state',
        );
        setState(() {
          _state = ProfileEmailFlowState.emailExists;
        });
      }
    } catch (e, st) {
      debugPrint('[ProfileEmailModal] ❌ _submit ERROR: $e');
      debugPrint('[ProfileEmailModal] ❌ _submit STACKTRACE: $st');

      setState(() {
        _state = ProfileEmailFlowState.initial;
        _error = 'Ошибка сервера';
      });
    }
  }

  Future<void> _recover() async {
    debugPrint('[ProfileEmailModal] _recover called');

    if (_state == ProfileEmailFlowState.sending) {
      debugPrint('[ProfileEmailModal] _recover aborted — already sending');
      return;
    }

    setState(() {
      _state = ProfileEmailFlowState.sending;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: _controller.text.trim(),
        emailRedirectTo: 'centry://auth',
      );

      setState(() {
        _state = ProfileEmailFlowState.recoverySent;
      });

      debugPrint('[ProfileEmailModal] Recovery OTP sent');
    } catch (e, st) {
      debugPrint('[ProfileEmailModal] ❌ _recover ERROR: $e');
      debugPrint('[ProfileEmailModal] ❌ _recover STACKTRACE: $st');

      setState(() {
        _state = ProfileEmailFlowState.emailExists;
        _error = 'Не удалось отправить письмо восстановления';
      });
    }
  }

  void _resetEmail() {
    debugPrint('[ProfileEmailModal] _resetEmail called');
    setState(() {
      _controller.clear();
      _state = ProfileEmailFlowState.initial;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showInput = _state == ProfileEmailFlowState.initial ||
        _state == ProfileEmailFlowState.emailExists;

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
                          onTap: () {
                            debugPrint(
                                '[ProfileEmailModal] Close button pressed');
                            Navigator.of(context).pop();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.close, size: 20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (showInput)
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        onChanged: (_) => setState(() {}),
                      ),
                    if (_state == ProfileEmailFlowState.emailExists) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Эта почта уже зарегистрирована\nВосстановите доступ',
                      ),
                    ],
                    if (_state == ProfileEmailFlowState.confirmSent) ...[
                      const SizedBox(height: 16),
                      const Text('Письмо для подтверждения отправлено'),
                      const SizedBox(height: 4),
                      const Text(
                        'Проверьте папку «Спам»',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _resetEmail,
                        child: Text(
                          'Ошиблись в адресе? Введите ещё раз',
                          style: TextStyle(
                            color: colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    if (_state == ProfileEmailFlowState.recoverySent) ...[
                      const SizedBox(height: 16),
                      const Text('Письмо для восстановления отправлено'),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    if (_state == ProfileEmailFlowState.initial)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: (_state == ProfileEmailFlowState.initial && _validEmail)
                                  ? colors.primary
                                  : Colors.grey.shade700,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: !_validEmail ||
                                  _state == ProfileEmailFlowState.sending
                              ? null
                              : _submit,
                          child: const Text('Подтвердить'),
                        ),
                      ),
                    if (_state == ProfileEmailFlowState.emailExists)
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: (_state == ProfileEmailFlowState.initial && _validEmail)
                                  ? colors.primary
                                  : Colors.grey.shade700,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _state == ProfileEmailFlowState.sending
                              ? null
                              : _recover,
                          child: const Text('Восстановить'),
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
