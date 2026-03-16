import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/profile/profile_email_modal.dart';
import '../../features/profile/avatar_picker_screen.dart';
import '../../features/profile/privacy_settings_screen.dart';
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
      return _ProfileData(
        nickname: widget.nickname,
        publicId: widget.publicId,
        email: null,
        isGuest: true,
      );
    }
    return _loadFromServer();
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

    return _ProfileData(
      nickname: nickname,
      publicId: publicId,
      email: email,
      isGuest: email == null || email.trim().isEmpty,
      name: res['name'] as String?,
      gender: res['gender'] as String?,
      age: res['age'] as int?,
      avatarKind: (res['avatar_kind'] as String?) ?? 'none',
      avatarUrl: res['avatar_url'] as String?,
    );
  }

  void _reload() {
    setState(() {
      _future = _loadFromAuthoritativeSource();
    });
  }

  Future<void> _openRegistrationModal() async {
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
              onRetry: _reload,
            );
          }

          if (!snap.hasData) {
            return _ErrorState(
              message: 'Профиль недоступен',
              onRetry: _reload,
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
            profile: profile,
            onReload: _reload,
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
  final String? name;
  final String? gender;
  final int? age;
  final String avatarKind;
  final String? avatarUrl;

  _ProfileData({
    required this.nickname,
    required this.publicId,
    required this.email,
    required this.isGuest,
    this.name,
    this.gender,
    this.age,
    this.avatarKind = 'none',
    this.avatarUrl,
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
              Text(details!, textAlign: TextAlign.center, style: text.bodySmall),
            ],
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
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
            Text(nickname,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
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
  final _ProfileData profile;
  final VoidCallback onReload;

  const _ProfileContent({required this.profile, required this.onReload});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TOP ROW: аватар+ник | CentryMarket+Приватность
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AvatarWidget(
                      avatarKind: profile.avatarKind,
                      avatarUrl: profile.avatarUrl,
                      onReload: onReload,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TitleValue(
                            title: 'Никнейм:',
                            value: profile.nickname,
                            isPrimary: true,
                          ),
                          const SizedBox(height: 6),
                          _CopyableValue(
                            title: 'Public ID',
                            value: profile.publicId,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _CentryMarketCard(),
                  const SizedBox(height: 6),
                  _PrivacySettingsTextLink(),
                  const SizedBox(height: 2),
                  _MyPlacesTextLink(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ПОЛЯ
          _EditableNameField(value: profile.name, onReload: onReload),
          const SizedBox(height: 4),
          _EditableGenderField(value: profile.gender, onReload: onReload),
          const SizedBox(height: 4),
          _EditableAgeField(value: profile.age, onReload: onReload),

          const SizedBox(height: 14),

          // Email — под полями, мелко
          Text('Email',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.outline)),
          const SizedBox(height: 2),
          Text(profile.email ?? '',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.outline)),

          Divider(height: 32, color: colors.outlineVariant.withValues(alpha: 0.5)),

          // Заглушки — компактные строки
          const _StubRow(title: 'Описание'),
          const _StubRow(title: 'Мои фото'),
          const _StubRow(title: 'Мои видео'),
        ],
      ),
    );
  }
}

// =======================
// Avatar widget
// =======================

class _AvatarWidget extends StatelessWidget {
  final String avatarKind;
  final String? avatarUrl;
  final VoidCallback onReload;

  const _AvatarWidget({
    required this.avatarKind,
    required this.avatarUrl,
    required this.onReload,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AvatarPickerScreen()),
    );
    if (result == true) onReload();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Stack(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline, width: 2),
              borderRadius: BorderRadius.circular(10),
              color: colors.surfaceContainerHighest,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _avatarContent(colors),
            ),
          ),
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: colors.outline, width: 1),
              ),
              child: Icon(Icons.edit, size: 12, color: colors.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarContent(ColorScheme colors) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return Image.network(
        avatarUrl!,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(colors),
      );
    }
    return _placeholder(colors);
  }

  Widget _placeholder(ColorScheme colors) {
    return Center(
      child: Icon(Icons.person_outline, size: 32, color: colors.outline),
    );
  }
}

// =======================
// Editable fields
// =======================

class _EditableNameField extends StatelessWidget {
  final String? value;
  final VoidCallback onReload;

  const _EditableNameField({this.value, required this.onReload});

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _TextEditDialog(
        title: 'Имя',
        initialValue: value ?? '',
        maxLength: 50,
      ),
    );
    if (result == null) return;

    await Supabase.instance.client.rpc(
      'set_profile_name',
      params: {'p_name': result},
    );
    onReload();
  }

  @override
  Widget build(BuildContext context) {
    return _EditableRow(
      title: 'Имя',
      displayValue: value?.isNotEmpty == true ? value! : '—',
      onTap: () => _edit(context),
    );
  }
}

class _EditableGenderField extends StatelessWidget {
  final String? value;
  final VoidCallback onReload;

  const _EditableGenderField({this.value, required this.onReload});

  String _label(String? v) {
    switch (v) {
      case 'male':
        return 'Мужской';
      case 'female':
        return 'Женский';
      case 'unspecified':
        return 'Не указан';
      default:
        return '—';
    }
  }

  Future<void> _edit(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _GenderPickerSheet(current: value),
    );
    if (result == null) return;

    await Supabase.instance.client.rpc(
      'set_profile_gender',
      params: {'p_gender': result},
    );
    onReload();
  }

  @override
  Widget build(BuildContext context) {
    return _EditableRow(
      title: 'Пол',
      displayValue: _label(value),
      onTap: () => _edit(context),
    );
  }
}

class _EditableAgeField extends StatelessWidget {
  final int? value;
  final VoidCallback onReload;

  const _EditableAgeField({this.value, required this.onReload});

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (_) => _TextEditDialog(
        title: 'Возраст',
        initialValue: value?.toString() ?? '',
        maxLength: 2,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
    if (result == null) return;

    final age = result.isEmpty ? null : int.tryParse(result);
    await Supabase.instance.client.rpc(
      'set_profile_age',
      params: {'p_age': age},
    );
    onReload();
  }

  @override
  Widget build(BuildContext context) {
    return _EditableRow(
      title: 'Возраст',
      displayValue: value != null ? '$value' : '—',
      onTap: () => _edit(context),
    );
  }
}

// =======================
// Privacy settings — текстовая ссылка
// =======================

class _PrivacySettingsTextLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text('Настройки',
                style: text.bodySmall?.copyWith(color: colors.primary)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 14, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

// =======================
// Мои места — текстовая ссылка
// =======================

class _MyPlacesTextLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        final repo = PlacesRepositoryImpl(Supabase.instance.client);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MyPlacesScreen(repository: repo)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_outline, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text('Мои места',
                style: text.bodySmall?.copyWith(color: colors.primary)),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 14, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

// =======================
// Stub row (компактная строка-заглушка)
// =======================

class _StubRow extends StatelessWidget {
  final String title;

  const _StubRow({required this.title});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(title, style: text.bodyMedium),
          const Spacer(),
          Text('В разработке',
              style: text.bodySmall?.copyWith(color: colors.outline)),
        ],
      ),
    );
  }
}

// =======================
// Helpers: editable row
// =======================

class _EditableRow extends StatelessWidget {
  final String title;
  final String displayValue;
  final VoidCallback onTap;

  const _EditableRow({
    required this.title,
    required this.displayValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    // Текст ограничен половиной ширины — карандаш выровнен по одной линии.
    // Правая половина остаётся свободной зоной.
    final textWidth = MediaQuery.of(context).size.width / 2 - 24;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: textWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(displayValue,
                      style: text.bodyMedium,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 16, color: colors.outline),
          ],
        ),
      ),
    );
  }
}

// =======================
// Text edit dialog
// =======================

class _TextEditDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final int maxLength;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;

  const _TextEditDialog({
    required this.title,
    required this.initialValue,
    required this.maxLength,
    this.keyboardType = TextInputType.text,
    this.inputFormatters = const [],
  });

  @override
  State<_TextEditDialog> createState() => _TextEditDialogState();
}

class _TextEditDialogState extends State<_TextEditDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        autofocus: true,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

// =======================
// Gender picker sheet
// =======================

class _GenderPickerSheet extends StatelessWidget {
  final String? current;

  const _GenderPickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final options = [
      ('male', 'Мужской'),
      ('female', 'Женский'),
      ('unspecified', 'Не указан'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Пол', style: text.titleMedium),
            ),
            const Divider(height: 1),
            ...options.map((opt) {
              final isSelected = current == opt.$1;
              return ListTile(
                title: Text(opt.$2),
                trailing: isSelected
                    ? const Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(context).pop(opt.$1),
              );
            }),
            ListTile(
              title: const Text('Очистить'),
              textColor: Colors.red,
              onTap: () => Navigator.of(context).pop('unspecified'),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// AppBar: Tokens
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

// =======================
// UI components (read-only)
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

  const _CopyableValue({required this.title, required this.value});

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
