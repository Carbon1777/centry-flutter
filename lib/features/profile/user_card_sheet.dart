import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =======================
// Мини-данные профиля для списков
// =======================

class UserMiniProfile {
  final String userId;
  final String? nickname;
  final bool nicknameHidden;
  final String? avatarUrl;
  final bool avatarHidden;
  final String? name;
  final bool nameHidden;

  const UserMiniProfile({
    required this.userId,
    this.nickname,
    this.nicknameHidden = false,
    this.avatarUrl,
    this.avatarHidden = false,
    this.name,
    this.nameHidden = false,
  });

  factory UserMiniProfile.fromMap(String userId, Map<String, dynamic> m) {
    return UserMiniProfile(
      userId: userId,
      nickname: m['nickname'] as String?,
      nicknameHidden: m['nickname_hidden'] as bool? ?? false,
      avatarUrl: m['avatar_url'] as String?,
      avatarHidden: m['avatar_hidden'] as bool? ?? false,
      name: m['name'] as String?,
      nameHidden: m['name_hidden'] as bool? ?? false,
    );
  }
}

// =======================
// Bulk-загрузка профилей для списков
// =======================

Future<Map<String, UserMiniProfile>> loadUserMiniProfiles({
  required List<String> userIds,
  required String context,
}) async {
  if (userIds.isEmpty) return {};

  final res = await Supabase.instance.client.rpc(
    'get_user_cards_bulk',
    params: {
      'p_user_ids': userIds,
      'p_context': context,
    },
  );

  if (res == null) return {};

  final map = res as Map<String, dynamic>;
  return map.map((userId, data) {
    final m = data as Map<String, dynamic>;
    return MapEntry(userId, UserMiniProfile.fromMap(userId, m));
  });
}

// =======================
// Виджет аватара для списков
// =======================

class UserAvatarWidget extends StatelessWidget {
  final UserMiniProfile? profile;
  final double size;
  final BorderRadius borderRadius;

  const UserAvatarWidget({
    super.key,
    required this.profile,
    this.size = 48,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Аватар скрыт → рамочка с перечёркнутым глазом
    if (profile?.avatarHidden == true) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: colors.outlineVariant, width: 1.5),
        ),
        child: Icon(
          Icons.visibility_off_outlined,
          color: colors.outline,
          size: size * 0.45,
        ),
      );
    }

    final url = profile?.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(colors),
        ),
      );
    }

    return _placeholder(colors);
  }

  Widget _placeholder(ColorScheme colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: colors.surfaceContainerHighest,
      ),
      child: Icon(Icons.person_outline, color: colors.outline, size: size * 0.5),
    );
  }
}

// =======================
// Center dialog карточки профиля
// =======================

class UserCardSheet extends StatefulWidget {
  final String targetUserId;
  final String context;

  const UserCardSheet({
    super.key,
    required this.targetUserId,
    required this.context,
  });

  static Future<void> show(
    BuildContext context, {
    required String targetUserId,
    required String cardContext,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UserCardSheet(
        targetUserId: targetUserId,
        context: cardContext,
      ),
    );
  }

  @override
  State<UserCardSheet> createState() => _UserCardSheetState();
}

class _UserCardSheetState extends State<UserCardSheet> {
  late Future<_UserCard> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_UserCard> _load() async {
    final res = await Supabase.instance.client.rpc('get_user_card', params: {
      'p_target_user_id': widget.targetUserId,
      'p_context': widget.context,
    });

    if (res is! Map) throw StateError('invalid response');
    return _UserCard.fromMap(res.cast<String, dynamic>());
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          FutureBuilder<_UserCard>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text('Ошибка загрузки',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                );
              }
              return _CardContent(card: snap.data!);
            },
          ),

          // Крестик — правый верхний угол
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _close,
                iconSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Содержимое карточки
// =======================

class _CardContent extends StatelessWidget {
  final _UserCard card;

  const _CardContent({required this.card});

  String _genderLabel(String? g) {
    switch (g) {
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 44, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + nickname
          Row(
            children: [
              // Avatar
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outline),
                  borderRadius: BorderRadius.circular(10),
                  color: colors.surfaceContainerHighest,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _avatarWidget(card, colors),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Никнейм', style: text.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      card.nicknameHidden
                          ? 'Скрыто'
                          : (card.nickname?.isNotEmpty == true
                              ? card.nickname!
                              : 'Пользователь'),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: card.nicknameHidden ? colors.outline : null,
                        fontStyle: card.nicknameHidden
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: 14),

          _CardRow(
            label: 'Имя',
            value: card.nameHidden ? null : card.name,
            hidden: card.nameHidden,
          ),
          const SizedBox(height: 10),
          _CardRow(
            label: 'Пол',
            value: card.genderHidden ? null : _genderLabel(card.gender),
            hidden: card.genderHidden,
          ),
          const SizedBox(height: 10),
          _CardRow(
            label: 'Возраст',
            value: card.ageHidden
                ? null
                : (card.age != null ? '${card.age}' : null),
            hidden: card.ageHidden,
          ),

          const SizedBox(height: 16),

          // Полный профиль — правый нижний угол
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _FullProfileStub.show(context),
              child: Text(
                'Полный профиль',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarWidget(_UserCard card, ColorScheme colors) {
    if (card.avatarHidden) {
      return Icon(
        Icons.visibility_off_outlined,
        color: colors.outline,
        size: 28,
      );
    }
    if (card.avatarUrl != null && card.avatarUrl!.isNotEmpty) {
      return Image.network(
        card.avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person_outline, color: colors.outline),
      );
    }
    return Icon(Icons.person_outline, color: colors.outline);
  }
}

class _CardRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool hidden;

  const _CardRow({
    required this.label,
    required this.value,
    required this.hidden,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    final displayValue =
        hidden ? 'Скрыто' : (value?.isNotEmpty == true ? value! : '—');

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: text.bodySmall),
        ),
        Text(
          displayValue,
          style: text.bodyMedium?.copyWith(
            color: hidden ? colors.outline : null,
            fontStyle: hidden ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }
}

// =======================
// Заглушка полного профиля
// =======================

class _FullProfileStub {
  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FullProfileStubSheet(),
    );
  }
}

class _FullProfileStubSheet extends StatelessWidget {
  const _FullProfileStubSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 12),

              // Шапка
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'Полный профиль',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // Контент
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.manage_accounts_outlined,
                      size: 96,
                      color: theme.colorScheme.primary.withValues(alpha: 0.22),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Упссс, и мы хотели бы посмотреть, но будет доступно с релизом проекта. 😅',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
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
// Model
// =======================

class _UserCard {
  final String userId;
  final String? nickname;
  final bool nicknameHidden;
  final String? avatarKind;
  final String? avatarUrl;
  final bool avatarHidden;
  final String? name;
  final bool nameHidden;
  final String? gender;
  final bool genderHidden;
  final int? age;
  final bool ageHidden;

  const _UserCard({
    required this.userId,
    this.nickname,
    required this.nicknameHidden,
    this.avatarKind,
    this.avatarUrl,
    required this.avatarHidden,
    this.name,
    required this.nameHidden,
    this.gender,
    required this.genderHidden,
    this.age,
    required this.ageHidden,
  });

  factory _UserCard.fromMap(Map<String, dynamic> m) {
    return _UserCard(
      userId: m['user_id'] as String,
      nickname: m['nickname'] as String?,
      nicknameHidden: m['nickname_hidden'] as bool? ?? false,
      avatarKind: m['avatar_kind'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      avatarHidden: m['avatar_hidden'] as bool? ?? false,
      name: m['name'] as String?,
      nameHidden: m['name_hidden'] as bool? ?? false,
      gender: m['gender'] as String?,
      genderHidden: m['gender_hidden'] as bool? ?? false,
      age: m['age'] as int?,
      ageHidden: m['age_hidden'] as bool? ?? false,
    );
  }
}
