import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/profile_email_modal.dart';
import 'centry_market_screen.dart';
import '../../features/places/my_places_screen.dart';
import '../../data/places/places_repository_impl.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String nickname;
  final String publicId;
  final String? email;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.nickname,
    required this.publicId,
    required this.email,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<_ProfileData> _future;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();

    _future = _loadFromAuthoritativeSource();

    final auth = Supabase.instance.client.auth;
    _authSub = auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session != null) {
        setState(() {
          _future = _loadFromAuthoritativeSource();
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<_ProfileData> _loadFromAuthoritativeSource() async {
    final client = Supabase.instance.client;

    if (client.auth.currentSession == null) {
      return _guestFromWidgetSnapshot();
    }

    return _loadFromServer();
  }

  _ProfileData _guestFromWidgetSnapshot() {
    return _ProfileData(
      nickname: widget.nickname,
      publicId: widget.publicId,
      email: null,
      isGuest: true,
    );
  }

  Future<_ProfileData> _loadFromServer() async {
    final res = await Supabase.instance.client.rpc('current_user');

    if (res is! Map) {
      throw StateError('current_user returned invalid payload: $res');
    }

    final nickname = (res['nickname'] as String?) ?? '';
    final publicId = res['public_id'] as String?;
    final email = res['email'] as String?;

    if (publicId == null || publicId.isEmpty) {
      throw StateError('current_user missing public_id: $res');
    }

    final isGuest = email == null || email.trim().isEmpty;

    return _ProfileData(
      nickname: nickname,
      publicId: publicId,
      email: email,
      isGuest: isGuest,
    );
  }

  void _retry() {
    setState(() {
      _future = _loadFromAuthoritativeSource();
    });
  }

  Future<void> _openRegistrationModal() async {
    // ✅ Было: showModalBottomSheet
    // ✅ Стало: центральное окно (dialog)
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ProfileEmailModal(
        bootstrapResult: {
          'id': widget.userId,
          'nickname': widget.nickname,
          'public_id': widget.publicId,
          'state': 'GUEST',
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bodyH = 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: const [
          // Важно: правый отступ делаем таким же, как у body padding,
          // чтобы Tokens и Market были на одной вертикальной линии.
          Padding(
            padding: EdgeInsets.only(right: bodyH),
            child: _TokensAppBar(),
          ),
        ],
      ),
      body: FutureBuilder<_ProfileData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError) {
            return _ErrorState(
              message: 'Ошибка загрузки профиля',
              details: snap.error.toString(),
              onRetry: _retry,
            );
          }

          if (!snap.hasData) {
            return _ErrorState(
              message: 'Профиль недоступен',
              onRetry: _retry,
            );
          }

          final profile = snap.data!;

          if (profile.isGuest) {
            return _GuestProfileContent(
              nickname: profile.nickname,
              publicId: profile.publicId,
              onStartRegistration: _openRegistrationModal,
            );
          }

          return _ProfileContent(
            nickname: profile.nickname,
            publicId: profile.publicId,
            email: profile.email!,
          );
        },
      ),
    );
  }
}

// =======================
// Domain model (UI-only)
// =======================

class _ProfileData {
  final String nickname;
  final String publicId;
  final String? email;
  final bool isGuest;

  _ProfileData({
    required this.nickname,
    required this.publicId,
    required this.email,
    required this.isGuest,
  });
}

// =======================
// Error UI
// =======================

class _ErrorState extends StatelessWidget {
  final String message;
  final String? details;
  final VoidCallback onRetry;

  const _ErrorState({
    required this.message,
    this.details,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center, style: text.bodyLarge),
            if (details != null) ...[
              const SizedBox(height: 12),
              Text(details!,
                  textAlign: TextAlign.center, style: text.bodySmall),
            ],
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// Guest UI
// =======================

class _GuestProfileContent extends StatelessWidget {
  final String nickname;
  final String publicId;
  final VoidCallback onStartRegistration;

  const _GuestProfileContent({
    required this.nickname,
    required this.publicId,
    required this.onStartRegistration,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nickname,
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Public ID: $publicId', style: text.bodySmall),
            const SizedBox(height: 24),
            Text(
              'Профиль доступен только зарегистрированным пользователям',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onStartRegistration,
              child: const Text('Пройти регистрацию'),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// User UI
// =======================

class _ProfileContent extends StatelessWidget {
  final String nickname;
  final String publicId;
  final String email;

  const _ProfileContent({
    required this.nickname,
    required this.publicId,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      // Поднимаем оранжевый блок максимально вверх за счёт:
      // 1) уменьшения top padding,
      // 2) уменьшения вертикального разрыва между TOP ROW и DETAILS BLOCK.
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==========================
          // TOP ROW (yellow block + right actions column)
          // ==========================
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT: Avatar + Nickname + Public ID
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outline, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TitleValue(
                            title: 'Никнейм:',
                            value: nickname,
                            isPrimary: true,
                          ),
                          const SizedBox(height: 6),
                          _CopyableValue(
                            title: 'Public ID',
                            value: publicId,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // RIGHT: Actions
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _CentryMarketCard(),
                  const SizedBox(height: 6),
                  _MyPlacesCard(),
                ],
              ),
            ],
          ),

          // Было 16 — уменьшаем, чтобы оранжевый блок поднялся,
          // но контент "не поехал" (всё остаётся в том же порядке/сетке).
          const SizedBox(height: 8),

          // ==========================
          // DETAILS BLOCK (orange block) - left aligned under the top row
          // ==========================
          _TitleValue(title: 'Email', value: email),
          const SizedBox(height: 12),
          const _PlaceholderValue(title: 'Имя'),
          const SizedBox(height: 6),
          const _PlaceholderValue(title: 'Пол'),
          const SizedBox(height: 6),
          const _PlaceholderValue(title: 'Возраст'),

          const SizedBox(height: 48),

          Center(
            child: Column(
              children: [
                Text('Профиль', style: text.titleMedium),
                const SizedBox(height: 8),
                Text('В разработке', style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// AppBar: Tokens (обведён целиком)
// =======================

class _TokensAppBar extends StatelessWidget {
  const _TokensAppBar();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.monetization_on_outlined, size: 16),
          const SizedBox(width: 6),
          Text('Tokens', style: text.bodyMedium),
          const SizedBox(width: 8),
          Text('—', style: text.bodyMedium),
        ],
      ),
    );
  }
}

// =======================
// CentryMarket Card
// =======================

class _CentryMarketCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CentryMarketScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront, size: 16),
              const SizedBox(width: 8),
              Text(
                'CentryMarket',
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyPlacesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        splashColor: colors.primary.withOpacity(0.15),
        onTap: () {
          final repo = PlacesRepositoryImpl(Supabase.instance.client);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MyPlacesScreen(repository: repo)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bookmark_outline, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Мои места',
                style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
// UI components
// =======================

class _TitleValue extends StatelessWidget {
  final String title;
  final String value;
  final bool isPrimary;

  const _TitleValue({
    required this.title,
    required this.value,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: isPrimary
              ? text.titleLarge?.copyWith(fontWeight: FontWeight.w600)
              : text.bodyMedium,
        ),
      ],
    );
  }
}

class _CopyableValue extends StatelessWidget {
  final String title;
  final String value;

  const _CopyableValue({
    required this.title,
    required this.value,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Скопировано'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.bodySmall),
        const SizedBox(height: 2),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _copy(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: text.bodyMedium),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.copy, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceholderValue extends StatelessWidget {
  final String title;

  const _PlaceholderValue({required this.title});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: text.bodySmall),
        const SizedBox(height: 2),
        Text('—', style: text.bodyMedium),
      ],
    );
  }
}
