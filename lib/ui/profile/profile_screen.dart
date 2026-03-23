import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/profile_photos/profile_photo_dto.dart';
import '../../data/profile_photos/profile_photos_repository_impl.dart';
import '../../features/profile/photo_crop_screen.dart';
import '../../features/profile/photo_fullscreen_viewer.dart';
import '../../features/profile/profile_email_modal.dart';
import '../../features/profile/avatar_picker_screen.dart';
import '../../features/profile/privacy_settings_screen.dart';
import '../../features/profile/leisure_constants.dart';
import 'centry_market_screen.dart';
import '../../features/places/my_places_screen.dart';
import '../../data/places/places_repository_impl.dart';
import '../../data/bonus/bonus_repository_impl.dart';
import '../../data/leaderboard/leaderboard_repository_impl.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../common/center_toast.dart';
import '../blocks/blocks_screen.dart';
import '../attention_signs/attention_sign_box_screen.dart';

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
      city: res['city'] as String?,
      restPreferences: List<String>.from(res['rest_preferences'] as List? ?? []),
      restDislikes: List<String>.from(res['rest_dislikes'] as List? ?? []),
      socialFormat: res['social_format'] as String?,
      restTempo: res['rest_tempo'] as String?,
      meetingTimePreferences: List<String>.from(res['meeting_time_preferences'] as List? ?? []),
      vibe: res['vibe'] as String?,
      shortBio: res['short_bio'] as String?,
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: bodyH),
            child: _TokensAppBar(userId: widget.userId),
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
            userId: widget.userId,
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
  final String? city;
  final String avatarKind;
  final String? avatarUrl;
  final List<String> restPreferences;
  final List<String> restDislikes;
  final String? socialFormat;
  final String? restTempo;
  final List<String> meetingTimePreferences;
  final String? vibe;
  final String? shortBio;

  _ProfileData({
    required this.nickname,
    required this.publicId,
    required this.email,
    required this.isGuest,
    this.name,
    this.gender,
    this.age,
    this.city,
    this.avatarKind = 'none',
    this.avatarUrl,
    this.restPreferences = const [],
    this.restDislikes = const [],
    this.socialFormat,
    this.restTempo,
    this.meetingTimePreferences = const [],
    this.vibe,
    this.shortBio,
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
  final String userId;

  const _ProfileContent({
    required this.profile,
    required this.onReload,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                // Stack: левый контент на всю высоту + правая колонка Positioned
                // Stack сам становится высотой левого контента → Positioned внутри bounds → нет конфликтов тапов
                Stack(
                  children: [
                    // Левый контент: полная ширина.
                    // Только строка аватара/ника имеет отступ справа под правую колонку.
                    // Поля и email — без ограничений по ширине.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Аватар + ник: с отступом справа чтобы не залезать под правую колонку
                        Padding(
                          padding: const EdgeInsets.only(right: 150),
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

                        const SizedBox(height: 6),

                        // ПОЛЯ — на полную ширину, контент не достаёт до правой колонки
                        _EditableCityField(value: profile.city, onReload: onReload),
                        _EditableNameField(value: profile.name, onReload: onReload),
                        _EditableGenderField(value: profile.gender, onReload: onReload),
                        _EditableAgeField(value: profile.age, onReload: onReload),

                        // Email — Expanded, полная ширина, не обрезается
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 72,
                                child: Text('Email',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: colors.outline)),
                              ),
                              Expanded(
                                child: Text(
                                  profile.email ?? '',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Правая колонка: Positioned внутри Stack bounds — тапы без конфликтов
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _CentryMarketCard(userId: userId),
                          const SizedBox(height: 6),
                          _PrivacySettingsTextLink(),
                          const SizedBox(height: 2),
                          _BlockingTextLink(userId: userId),
                          const SizedBox(height: 2),
                          _MyPlacesTextLink(),
                          const SizedBox(height: 2),
                          _RatingTextLink(userId: userId),
                          const SizedBox(height: 6),
                          _AttentionSignBoxIcon(userId: userId),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Секция "Стиль отдыха" — нижняя часть профиля
                _LeisureSection(
                  restPreferences: profile.restPreferences,
                  restDislikes: profile.restDislikes,
                  socialFormat: profile.socialFormat,
                  restTempo: profile.restTempo,
                  meetingTimePreferences: profile.meetingTimePreferences,
                  vibe: profile.vibe,
                  shortBio: profile.shortBio,
                  onReload: onReload,
                ),
              ],
            ),
          ),
        ),

        // Версия сборки — прибита к низу экрана
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: _AppVersionLabel(),
        ),
      ],
    ),
            _ProfileMediaSheet(
              availableHeight: constraints.maxHeight,
              userId: userId,
            ),
          ],
        );
      },
    );
  }
}

// =======================
// App Version Label
// =======================

// =======================
// Коробка знаков внимания — карточка в профиле
// =======================

class _AttentionSignBoxIcon extends StatelessWidget {
  final String userId;

  const _AttentionSignBoxIcon({required this.userId});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      containedInkWell: true,
      highlightShape: BoxShape.circle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttentionSignBoxScreen(appUserId: userId),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Text('🎁', style: TextStyle(fontSize: 63)),
      ),
    );
  }
}

// =======================
// App Version Label
// =======================

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  late final Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String?> _load() async {
    try {
      final data = await Supabase.instance.client
          .rpc('get_app_version_v1') as Map<String, dynamic>?;
      if (data == null) return null;
      final phase = data['phase'] as String? ?? '';
      final version = data['version'] as String? ?? '';
      final build = data['build'] as int? ?? 0;
      return '$phase $version.$build';
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final label = snapshot.data;
        if (label == null) return const SizedBox.shrink();
        return Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.3),
                ),
          ),
        );
      },
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

class _EditableCityField extends StatelessWidget {
  final String? value;
  final VoidCallback onReload;

  const _EditableCityField({this.value, required this.onReload});

  Future<void> _edit(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _CityPickerSheet(current: value),
    );
    if (result == null) return;

    await Supabase.instance.client.rpc(
      'set_profile_city',
      params: {'p_city': result.isEmpty ? null : result},
    );
    onReload();
  }

  @override
  Widget build(BuildContext context) {
    return _EditableRow(
      title: 'Город',
      displayValue: value?.isNotEmpty == true ? value! : '—',
      onTap: () => _edit(context),
    );
  }
}

class _CityPickerSheet extends StatelessWidget {
  final String? current;

  const _CityPickerSheet({this.current});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    const options = [
      'Москва',
      'Санкт-Петербург',
      'Казань',
      'Нижний Новгород',
      'Краснодар',
      'Ростов-на-Дону',
      'Новосибирск',
      'Сочи',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Город', style: text.titleMedium),
            ),
            const Divider(height: 1),
            ...options.map((city) {
              final isSelected = current == city;
              return ListTile(
                title: Text(city),
                trailing: isSelected ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.of(context).pop(city),
              );
            }),
            ListTile(
              title: const Text('Очистить'),
              textColor: Colors.red,
              onTap: () => Navigator.of(context).pop(''),
            ),
          ],
        ),
      ),
    );
  }
}

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
// Блокировка — текстовая ссылка
// =======================

class _BlockingTextLink extends StatelessWidget {
  final String userId;

  const _BlockingTextLink({required this.userId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => BlocksScreen(appUserId: userId)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_outlined, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text('Блокировка',
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
// Рейтинг — текстовая ссылка
// =======================

class _RatingTextLink extends StatelessWidget {
  final String userId;

  const _RatingTextLink({required this.userId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        final repo = LeaderboardRepositoryImpl(Supabase.instance.client);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LeaderboardScreen(
              repository: repo,
              appUserId: userId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.leaderboard_outlined, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text('Рейтинг',
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

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(title,
                  style: text.bodySmall?.copyWith(color: colors.outline)),
            ),
            SizedBox(
              width: 110,
              child: Text(displayValue,
                  style: text.bodyMedium,
                  overflow: TextOverflow.ellipsis),
            ),
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

class _TokensAppBar extends StatefulWidget {
  final String userId;

  const _TokensAppBar({required this.userId});

  @override
  State<_TokensAppBar> createState() => _TokensAppBarState();
}

class _TokensAppBarState extends State<_TokensAppBar> {
  late final Future<int?> _balanceFuture;

  @override
  void initState() {
    super.initState();
    _balanceFuture = BonusRepositoryImpl(Supabase.instance.client)
        .getSummary(appUserId: widget.userId)
        .then<int?>((s) => s.currentBalance)
        .catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<int?>(
      future: _balanceFuture,
      builder: (context, snapshot) {
        final label = snapshot.hasData ? '${snapshot.data}' : '—';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              Text(label, style: text.bodyMedium),
            ],
          ),
        );
      },
    );
  }
}

// =======================
// CentryMarket Card
// =======================

class _CentryMarketCard extends StatelessWidget {
  final String userId;

  const _CentryMarketCard({required this.userId});

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
            MaterialPageRoute(
              builder: (_) => CentryMarketScreen(userId: userId),
            ),
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
    await showCenterToast(context, message: 'ID пользователя скопирован');
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


// =======================
// Leisure section (view + inline edit)
// =======================

class _LeisureSection extends StatefulWidget {
  final List<String> restPreferences;
  final List<String> restDislikes;       // pass-through, not shown
  final String? socialFormat;
  final String? restTempo;               // pass-through, not shown
  final List<String> meetingTimePreferences;
  final String? vibe;
  final String? shortBio;               // pass-through, not shown
  final VoidCallback onReload;

  const _LeisureSection({
    required this.restPreferences,
    required this.restDislikes,
    this.socialFormat,
    this.restTempo,
    required this.meetingTimePreferences,
    this.vibe,
    this.shortBio,
    required this.onReload,
  });

  @override
  State<_LeisureSection> createState() => _LeisureSectionState();
}

class _LeisureSectionState extends State<_LeisureSection> {
  late List<String> _restPreferences;
  late List<String> _restDislikes;
  late String? _socialFormat;
  late String? _restTempo;
  late List<String> _meetingTimePreferences;
  late String? _vibe;
  late String? _shortBio;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_LeisureSection old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    _restPreferences = List.from(widget.restPreferences);
    _restDislikes = List.from(widget.restDislikes);
    _socialFormat = widget.socialFormat;
    _restTempo = widget.restTempo;
    _meetingTimePreferences = List.from(widget.meetingTimePreferences);
    _vibe = widget.vibe;
    _shortBio = widget.shortBio;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('set_profile_leisure', params: {
        'p_rest_preferences': _restPreferences,
        'p_rest_dislikes': _restDislikes,
        'p_social_format': _socialFormat,
        'p_rest_tempo': _restTempo,
        'p_meeting_time_preferences': _meetingTimePreferences,
        'p_vibe': _vibe,
        'p_short_bio': _shortBio,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
        // revert on error
        _sync();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickMulti({
    required String title,
    required List<LeisureOption> options,
    required List<String> current,
    required int maxCount,
    required void Function(List<String>) onChanged,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MultiPickerSheet(
        title: title,
        options: options,
        current: current,
        maxCount: maxCount,
      ),
    );
    if (result != null) {
      setState(() => onChanged(result));
      await _save();
    }
  }

  Future<void> _pickSingle({
    required String title,
    required List<LeisureOption> options,
    required String? current,
    required void Function(String?) onChanged,
  }) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _SinglePickerSheet(
        title: title,
        options: options,
        current: current,
      ),
    );
    // result == '' means "deselect"
    if (result != null) {
      setState(() => onChanged(result.isEmpty ? null : result));
      await _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 8),
        Row(
          children: [
            Text(
              'Стиль отдыха',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (_saving) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colors.outline,
                ),
              ),
            ],
          ],
        ),
        

        _LeisureRow(
          title: 'Как люблю отдыхать',
          selectedKeys: _restPreferences,
          options: LeisureConstants.restPreferences,
          hint: 'до 3 вариантов',
          onTap: () => _pickMulti(
            title: 'Как люблю отдыхать',
            options: LeisureConstants.restPreferences,
            current: _restPreferences,
            maxCount: 3,
            onChanged: (v) => _restPreferences = v,
          ),
        ),

        _LeisureRow(
          title: 'Формат компании',
          selectedKeys: _socialFormat != null ? [_socialFormat!] : [],
          options: LeisureConstants.socialFormats,
          hint: 'выбери один',
          onTap: () => _pickSingle(
            title: 'Формат компании',
            options: LeisureConstants.socialFormats,
            current: _socialFormat,
            onChanged: (v) => _socialFormat = v,
          ),
        ),

        _LeisureRow(
          title: 'Когда удобнее встречаться',
          selectedKeys: _meetingTimePreferences,
          options: LeisureConstants.meetingTimes,
          hint: 'до 2 вариантов',
          onTap: () => _pickMulti(
            title: 'Когда удобнее встречаться',
            options: LeisureConstants.meetingTimes,
            current: _meetingTimePreferences,
            maxCount: 2,
            onChanged: (v) => _meetingTimePreferences = v,
          ),
        ),

        _LeisureRow(
          title: 'Мой вайб',
          selectedKeys: _vibe != null ? [_vibe!] : [],
          options: LeisureConstants.vibes,
          hint: 'выбери один',
          onTap: () => _pickSingle(
            title: 'Мой вайб',
            options: LeisureConstants.vibes,
            current: _vibe,
            onChanged: (v) => _vibe = v,
          ),
        ),
      ],
    );
  }
}

// =======================
// Leisure row (compact)
// =======================

class _LeisureRow extends StatelessWidget {
  final String title;
  final List<String> selectedKeys;
  final List<LeisureOption> options;
  final String hint;
  final VoidCallback onTap;

  const _LeisureRow({
    required this.title,
    required this.selectedKeys,
    required this.options,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEmpty = selectedKeys.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 0, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.bodySmall?.copyWith(color: colors.outline),
                  ),
                  const SizedBox(height: 3),
                  if (isEmpty)
                    Text(
                      hint,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.28),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: selectedKeys.map((key) {
                        final opt = LeisureConstants.findByKey(options, key);
                        if (opt == null) return const SizedBox.shrink();
                        return _LeisureChip(
                          label: '${opt.emoji} ${opt.label}',
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _LeisureChip extends StatelessWidget {
  final String label;

  const _LeisureChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Text(label, style: textTheme.bodySmall, maxLines: 1),
    );
  }
}

// =======================
// Multi picker sheet
// =======================

class _MultiPickerSheet extends StatefulWidget {
  final String title;
  final List<LeisureOption> options;
  final List<String> current;
  final int maxCount;

  const _MultiPickerSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.maxCount,
  });

  @override
  State<_MultiPickerSheet> createState() => _MultiPickerSheetState();
}

class _MultiPickerSheetState extends State<_MultiPickerSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.current);
  }

  void _toggle(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else if (_selected.length < widget.maxCount) {
        _selected.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final atLimit = _selected.length >= widget.maxCount;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Row(
                  children: [
                    Text(
                      'до ${widget.maxCount}',
                      style: textTheme.bodySmall?.copyWith(
                        color:
                            atLimit ? colors.primary : colors.outline,
                        fontWeight: atLimit
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(_selected),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Готово'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...widget.options.map((opt) {
              final isSelected = _selected.contains(opt.key);
              final isDisabled = atLimit && !isSelected;
              return _PickerTile(
                option: opt,
                isSelected: isSelected,
                isDisabled: isDisabled,
                onTap: isDisabled ? null : () => _toggle(opt.key),
              );
            }),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// =======================
// Single picker sheet
// =======================

class _SinglePickerSheet extends StatelessWidget {
  final String title;
  final List<LeisureOption> options;
  final String? current;

  const _SinglePickerSheet({
    required this.title,
    required this.options,
    this.current,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style:
                  textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            ...options.map((opt) {
              final isSelected = current == opt.key;
              return _PickerTile(
                option: opt,
                isSelected: isSelected,
                isDisabled: false,
                // tap selected → deselect (pass empty string = "clear")
                onTap: () => Navigator.of(context)
                    .pop(isSelected ? '' : opt.key),
              );
            }),
            if (current != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Очистить'),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// =======================
// Picker tile (shared)
// =======================

class _PickerTile extends StatelessWidget {
  final LeisureOption option;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const _PickerTile({
    required this.option,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Opacity(
      opacity: isDisabled ? 0.38 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label, style: textTheme.bodyMedium),
                    if (option.subLabel.isNotEmpty)
                      Text(
                        option.subLabel,
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.outline),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: isSelected ? colors.primary : colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
// Profile Media Sheet
// =======================

class _ProfileMediaSheet extends StatefulWidget {
  final double availableHeight;
  final String userId;

  const _ProfileMediaSheet({
    required this.availableHeight,
    required this.userId,
  });

  @override
  State<_ProfileMediaSheet> createState() => _ProfileMediaSheetState();
}

class _ProfileMediaSheetState extends State<_ProfileMediaSheet> {
  static const double _kCollapsedHeight = 76;
  static const Duration _kAnimDuration = Duration(milliseconds: 320);
  static const int _kMaxPhotos = 9;

  // Sheet expand state
  bool _expanded = false;
  double _dragOffsetY = 0;

  // Photos
  final _repo = ProfilePhotosRepositoryImpl();
  List<ProfilePhotoDto> _photos = [];
  bool _photosLoaded = false;
  bool _isUploading = false;

  // Delete mode
  bool _deleteMode = false;
  Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _repo.getPhotos(widget.userId);
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _photosLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _photosLoaded = true);
    }
  }

  // ── Expand / collapse ──

  void _toggle() => setState(() => _expanded = !_expanded);

  void _onDragUpdate(DragUpdateDetails d) {
    _dragOffsetY += d.delta.dy;
    if (!_expanded && _dragOffsetY <= -10) {
      setState(() { _expanded = true; _dragOffsetY = 0; });
    } else if (_expanded && _dragOffsetY >= 12) {
      setState(() { _expanded = false; _dragOffsetY = 0; });
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (!_expanded && v < -220) { setState(() => _expanded = true); }
    else if (_expanded && v > 220) { setState(() => _expanded = false); }
    _dragOffsetY = 0;
  }

  // ── Upload ──

  Future<void> _showAddPhotoOptions() async {
    final freeSlots = _kMaxPhotos - _photos.length;
    if (freeSlots <= 0) return;

    final result = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    if (result == ImageSource.camera) {
      await _pickFromCamera();
    } else {
      await _pickFromGallery(freeSlots);
    }
  }

  Future<void> _pickFromCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera, imageQuality: 92,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await _cropAndUpload(bytes);
  }

  Future<void> _pickFromGallery(int freeSlots) async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 92);
    if (picked.isEmpty || !mounted) return;

    List<XFile> toProcess = picked;
    if (picked.length > freeSlots) {
      toProcess = picked.sublist(0, freeSlots);
      if (mounted) {
        showCenterToast(
          context,
          message: 'Во время бета-тестирования доступно до $_kMaxPhotos фото. '
              'Сейчас свободно только $freeSlots мест, '
              'поэтому добавлены первые $freeSlots фото.',
          duration: const Duration(seconds: 4),
        );
      }
    }

    // Все фото из галереи загружаются как есть (без кропа).
    // Кроп доступен через «Заменить» в fullscreen viewer.
    await _uploadBatch(toProcess);
  }

  Future<void> _cropAndUpload(Uint8List bytes) async {
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => PhotoCropScreen(imageBytes: bytes)),
    );
    if (croppedBytes == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      await _uploadOne(croppedBytes);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadBatch(List<XFile> files) async {
    setState(() => _isUploading = true);
    try {
      for (final file in files) {
        if (!mounted) return;
        final bytes = await file.readAsBytes();
        await _uploadOne(bytes);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadOne(Uint8List bytes) async {
    try {
      final client = Supabase.instance.client;
      final authUserId = client.auth.currentUser?.id;
      if (authUserId == null) return;

      // Сжимаем в WebP — убирает EXIF, нормализует ориентацию
      final webpBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1920, minHeight: 1920,
        quality: 88,
        format: CompressFormat.webp,
        keepExif: false,
      );

      final storagePath = '$authUserId/${_generateUuid()}.webp';

      await client.storage.from('profile-photos').uploadBinary(
        storagePath, webpBytes,
        fileOptions: const FileOptions(contentType: 'image/webp'),
      );

      final newPhoto = await _repo.addPhoto(
        storageKey: storagePath,
        sizeBytes: webpBytes.length,
      );

      if (mounted) setState(() => _photos = [..._photos, newPhoto]);
    } catch (_) {
      if (mounted) {
        showCenterToast(context, message: 'Ошибка загрузки фото', isError: true);
      }
    }
  }

  // ── Delete mode ──

  void _enterDeleteMode() => setState(() {
    _deleteMode = true;
    _selectedIds = {};
  });

  void _exitDeleteMode() => setState(() {
    _deleteMode = false;
    _selectedIds = {};
  });

  void _toggleSelection(String id) => setState(() {
    final updated = Set<String>.from(_selectedIds);
    if (updated.contains(id)) { updated.remove(id); } else { updated.add(id); }
    _selectedIds = updated;
  });

  Future<void> _confirmAndDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: Text(
          count == 1
              ? 'Выбранное фото будет удалено без возможности восстановления.'
              : 'Выбранные фото ($count) будут удалены без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ids = _selectedIds.toList();

      // Сохраняем storage keys до удаления, чтобы очистить storage на клиенте
      final storageKeys = _photos
          .where((p) => ids.contains(p.id))
          .map((p) => p.storageKey)
          .toList();

      await _repo.deletePhotos(ids);

      // Клиентская очистка storage (best-effort, не блокирует UI)
      if (storageKeys.isNotEmpty) {
        Supabase.instance.client.storage
            .from('profile-photos')
            .remove(storageKeys)
            .ignore();
      }

      if (!mounted) return;
      setState(() {
        _photos = _photos.where((p) => !ids.contains(p.id)).toList();
        _exitDeleteMode();
      });
    } catch (e) {
      if (mounted) {
        await showCenterToast(context, message: 'Ошибка удаления', isError: true);
      }
    }
  }

  // ── Reorder ──

  Future<void> _onPhotoSwap(int fromIdx, int toIdx) async {
    if (fromIdx == toIdx) return;
    final photoA = _photos[fromIdx];
    final photoB = _photos[toIdx];

    // Оптимистичный UI
    final updated = List<ProfilePhotoDto>.from(_photos);
    updated[fromIdx] = photoB;
    updated[toIdx] = photoA;
    setState(() => _photos = updated);

    try {
      await _repo.reorderPhotos(idA: photoA.id, idB: photoB.id);
    } catch (_) {
      if (mounted) {
        showCenterToast(context, message: 'Ошибка сохранения порядка', isError: true);
        await _loadPhotos();
      }
    }
  }

  void _openFullscreen(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoFullscreenViewer(
        photos: _photos,
        initialIndex: index,
        isOwner: true,
        onPhotoReplaced: _loadPhotos,
      ),
    ));
  }

  static String _generateUuid() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-${h.substring(12,16)}'
        '-${h.substring(16,20)}-${h.substring(20)}';
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxH = widget.availableHeight
        .clamp(_kCollapsedHeight, widget.availableHeight)
        .toDouble();
    final targetH = _expanded ? maxH : _kCollapsedHeight;
    final hasPhotos = _photos.isNotEmpty;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _kAnimDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: targetH,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
            left: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
            right: BorderSide(color: colors.outline.withValues(alpha: 0.2)),
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Drag handle + title ──
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _kCollapsedHeight - 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 52, height: 5,
                          decoration: BoxDecoration(
                            color: colors.onSurface.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Мои фото и видео',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),

              // ── Expanded content ──
              if (_expanded)
                Flexible(
                  fit: FlexFit.tight,
                  child: LayoutBuilder(builder: (context, constraints) {
                    if (constraints.maxHeight < 20) return const SizedBox.shrink();
                    return Column(
                      children: [
                        Divider(height: 1, thickness: 1,
                            color: colors.outline.withValues(alpha: 0.2)),
                        Expanded(child: _buildExpandedContent(
                          colors, textTheme, hasPhotos,
                        )),
                      ],
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(
    ColorScheme colors,
    TextTheme textTheme,
    bool hasPhotos,
  ) {
    if (!_photosLoaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // «Выбрать / Удалить / Отменить» — только когда есть фото
          if (hasPhotos)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _deleteMode
                        ? (_selectedIds.isNotEmpty
                            ? _confirmAndDelete
                            : _exitDeleteMode)
                        : _enterDeleteMode,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Text(
                        _deleteMode
                            ? (_selectedIds.isNotEmpty ? 'Удалить' : 'Отменить')
                            : 'Выбрать',
                        key: ValueKey(_deleteMode
                            ? (_selectedIds.isNotEmpty ? 'del' : 'cancel')
                            : 'sel'),
                        style: textTheme.labelMedium?.copyWith(
                          color: (_deleteMode && _selectedIds.isNotEmpty)
                              ? Colors.red
                              : colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Сетка 3×9
          _buildGrid(colors),

          // Инфо-текст
          const SizedBox(height: 20),
          Text(
            'Во время бета-тестирования можно добавить до 9 фото. '
            'С релизом проекта появится возможность загружать '
            'больше фото и видео.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.55),
              height: 1.5,
            ),
          ),

          // Индикатор загрузки
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('Загружаем фото...',
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.6),
                      )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGrid(ColorScheme colors) {
    return AspectRatio(
      aspectRatio: 1,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemCount: _kMaxPhotos,
        itemBuilder: (ctx, i) => _buildCell(ctx, i, colors),
      ),
    );
  }

  Widget _buildCell(BuildContext context, int index, ColorScheme colors) {
    final hasPhoto = index < _photos.length;

    // Пустая ячейка
    if (!hasPhoto) {
      return GestureDetector(
        onTap: (!_isUploading && !_deleteMode) ? _showAddPhotoOptions : null,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Icon(Icons.add_circle_outline, size: 26,
                color: colors.onSurface.withValues(alpha: 0.3)),
          ),
        ),
      );
    }

    final photo = _photos[index];
    final isSelected = _selectedIds.contains(photo.id);

    // Режим выделения
    if (_deleteMode) {
      return GestureDetector(
        onTap: () => _toggleSelection(photo.id),
        child: _PhotoCell(
          photo: photo,
          isSelected: isSelected,
          showCheckbox: true,
          colors: colors,
        ),
      );
    }

    // Нормальный режим — drag & drop + tap
    return LongPressDraggable<int>(
      data: index,
      delay: const Duration(milliseconds: 400),
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: 110, height: 110,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _PhotoImage(photo: photo),
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: colors.outline.withValues(alpha: 0.3), width: 1.5,
          ),
        ),
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != index,
        onAcceptWithDetails: (d) => _onPhotoSwap(d.data, index),
        builder: (ctx, candidates, _) {
          final isTarget = candidates.isNotEmpty;
          return GestureDetector(
            onTap: () => _openFullscreen(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: isTarget
                    ? Border.all(color: colors.primary, width: 2.5)
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isTarget ? 4 : 6),
                child: _PhotoImage(photo: photo),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =======================
// Photo cell (with checkbox overlay)
// =======================

class _PhotoCell extends StatelessWidget {
  final ProfilePhotoDto photo;
  final bool isSelected;
  final bool showCheckbox;
  final ColorScheme colors;

  const _PhotoCell({
    required this.photo,
    required this.isSelected,
    required this.showCheckbox,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PhotoImage(photo: photo),
          if (showCheckbox)
            Container(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.35)
                  : Colors.black.withValues(alpha: 0.12),
            ),
          if (showCheckbox)
            Positioned(
              top: 6, right: 6,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22, height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? colors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? colors.primary : Colors.white,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

// =======================
// Photo image (cached)
// =======================

class _PhotoImage extends StatelessWidget {
  final ProfilePhotoDto photo;

  const _PhotoImage({required this.photo});

  @override
  Widget build(BuildContext context) {
    final dimColor =
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final iconColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3);

    return CachedNetworkImage(
      imageUrl: photo.publicUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => ColoredBox(
        color: dimColor,
        child: Center(child: Icon(Icons.image_outlined, color: iconColor)),
      ),
      errorWidget: (_, __, ___) => ColoredBox(
        color: dimColor,
        child: Center(
            child: Icon(Icons.broken_image_outlined, color: iconColor)),
      ),
    );
  }
}
