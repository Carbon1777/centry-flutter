import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'permissions_screen.dart';

class NicknameScreen extends StatefulWidget {
  final void Function(Map<String, dynamic> result) onBootstrapped;

  const NicknameScreen({super.key, required this.onBootstrapped});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final _controller = TextEditingController();

  bool _loading = false;
  String? _errorText;

  String get _value => _controller.text.trim();
  int get _length => _value.length;
  bool get _isValid => _length >= 2 && _length <= 20;

  String? get _lengthError {
    if (_length == 0) return null;
    if (_length < 2) return 'Минимум 2 символа';
    if (_length > 20) return 'Максимум 20 символов';
    return null;
  }

  Future<void> _submit() async {
    if (!_isValid || _loading) return;

    setState(() {
      _loading = true;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;

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
      appBar: AppBar(title: const Text('Никнейм')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Align(
                  alignment: const Alignment(0, -0.25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isValid && !_loading ? _submit : null,
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
