import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/profile_photos/profile_photo_dto.dart';
import '../../data/profile_photos/profile_photos_repository_impl.dart';
import '../../features/profile/leisure_constants.dart';
import '../../features/profile/photo_fullscreen_viewer.dart';
import '../../ui/common/center_toast.dart';

// =======================
// Мини-данные профиля для списков
// =======================

class UserMiniProfile {
  final String userId;
  final bool miniHidden;
  final String? nickname;
  final String? avatarUrl;
  final String? name;
  final DateTime? lastActiveAt;

  const UserMiniProfile({
    required this.userId,
    this.miniHidden = false,
    this.nickname,
    this.avatarUrl,
    this.name,
    this.lastActiveAt,
  });

  factory UserMiniProfile.fromMap(String userId, Map<String, dynamic> m) {
    return UserMiniProfile(
      userId: userId,
      miniHidden: m['mini_hidden'] as bool? ?? false,
      nickname: m['nickname'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      name: m['name'] as String?,
      lastActiveAt: m['last_active_at'] != null
          ? DateTime.parse(m['last_active_at'] as String)
          : null,
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
  }) async {
    final errorMsg = await showDialog<String?>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UserCardSheet(
        targetUserId: targetUserId,
        context: cardContext,
      ),
    );
    if (errorMsg != null && context.mounted) {
      await showCenterToast(context, message: errorMsg, isError: true);
    }
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
              final card = snap.data!;
              if (card.miniHidden) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Navigator.of(context, rootNavigator: true)
                      .pop('Пользователь закрыл возможность просмотра');
                });
                return const SizedBox.shrink();
              }
              return _CardContent(
                card: card,
                targetUserId: widget.targetUserId,
                cardContext: widget.context,
              );
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
  final String targetUserId;
  final String cardContext;

  const _CardContent({required this.card, required this.targetUserId, required this.cardContext});

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
                  child: _avatarWidget(colors),
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
                      card.nickname?.isNotEmpty == true
                          ? card.nickname!
                          : 'Пользователь',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
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

          _CardRow(label: 'Имя', value: card.name),
          const SizedBox(height: 10),
          _CardRow(label: 'Пол', value: _genderLabel(card.gender)),
          const SizedBox(height: 10),
          _CardRow(
            label: 'Возраст',
            value: card.age != null ? '${card.age}' : null,
          ),

          const SizedBox(height: 16),

          // Полный профиль — правый нижний угол
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                final rootNav = Navigator.of(context, rootNavigator: true);
                final overlayCtx = rootNav.overlay!.context;
                rootNav.pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _FullProfileSheet.showWithContext(
                    overlayCtx,
                    targetUserId: targetUserId,
                    cardContext: cardContext,
                  );
                });
              },
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

  Widget _avatarWidget(ColorScheme colors) {
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

  const _CardRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: text.bodySmall),
        ),
        Text(
          value?.isNotEmpty == true ? value! : '—',
          style: text.bodyMedium,
        ),
      ],
    );
  }
}

// =======================
// Полный профиль пользователя (просмотр)
// =======================

class _FullProfileSheet extends StatelessWidget {
  final _FullProfile profile;

  const _FullProfileSheet({required this.profile});

  static Future<void> showWithContext(
    BuildContext context, {
    required String targetUserId,
    required String cardContext,
  }) async {
    final Object? res;
    try {
      res = await Supabase.instance.client.rpc(
        'get_user_full_profile',
        params: {
          'p_target_user_id': targetUserId,
          'p_context': cardContext,
        },
      );
    } catch (_) {
      return;
    }
    if (res is! Map) return;
    final profile = _FullProfile.fromMap(res.cast<String, dynamic>());

    if (profile.fullProfileHidden) {
      if (context.mounted) {
        await showCenterToast(
          context,
          message: 'Пользователь закрыл возможность просмотра',
          isError: true,
        );
      }
      return;
    }

    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FullProfileSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: theme.dividerColor.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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

              const SizedBox(height: 4),
              const Divider(height: 1),

              // Тело
              Expanded(child: _FullProfileBody(profile: profile)),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================
// Тело полного профиля (контент + шторка фото)
// =======================

class _FullProfileBody extends StatelessWidget {
  final _FullProfile profile;

  const _FullProfileBody({required this.profile});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              child: _FullProfileContent(profile: profile),
            ),
            _FullProfileMediaSheet(
              availableHeight: constraints.maxHeight,
              targetUserId: profile.userId,
            ),
          ],
        );
      },
    );
  }
}

// =======================
// Контент полного профиля
// =======================

class _FullProfileContent extends StatelessWidget {
  final _FullProfile profile;

  const _FullProfileContent({required this.profile});

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Аватар (крупный) + ник под ним | поля справа
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Левая колонка: аватар + никнейм под ним
              Column(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.outline),
                      borderRadius: BorderRadius.circular(16),
                      color: colors.surfaceContainerHighest,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _avatarWidget(profile, colors),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Никнейм:', style: text.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    profile.nicknameHidden
                        ? 'Скрыто'
                        : (profile.nickname?.isNotEmpty == true
                            ? profile.nickname!
                            : 'Пользователь'),
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: profile.nicknameHidden ? colors.outline : null,
                      fontStyle: profile.nicknameHidden
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 16),

              // Правая колонка: инфо-поля
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _InfoRow(label: 'Город', value: profile.city),
                    _InfoRow(
                      label: 'Имя',
                      value: profile.nameHidden ? null : profile.name,
                      hidden: profile.nameHidden,
                    ),
                    _InfoRow(
                      label: 'Пол',
                      value: profile.genderHidden
                          ? null
                          : _genderLabel(profile.gender),
                      hidden: profile.genderHidden,
                    ),
                    _InfoRow(
                      label: 'Возраст',
                      value: profile.ageHidden
                          ? null
                          : (profile.age != null ? '${profile.age}' : null),
                      hidden: profile.ageHidden,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Стиль отдыха (read-only)
        _ViewLeisureSection(
          restPreferences: profile.restPreferences,
          socialFormat: profile.socialFormat,
          meetingTimePreferences: profile.meetingTimePreferences,
          vibe: profile.vibe,
        ),
      ],
    );
  }

  Widget _avatarWidget(_FullProfile p, ColorScheme colors) {
    if (p.avatarHidden) {
      return Icon(Icons.visibility_off_outlined, color: colors.outline, size: 32);
    }
    if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
      return Image.network(
        p.avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person_outline, color: colors.outline),
      );
    }
    return Icon(Icons.person_outline, color: colors.outline);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final bool hidden;

  const _InfoRow({
    required this.label,
    this.value,
    this.hidden = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    final displayValue =
        hidden ? 'Скрыто' : (value?.isNotEmpty == true ? value! : '—');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: colors.outline),
            ),
          ),
          Text(
            displayValue,
            style: text.bodyMedium?.copyWith(
              color: hidden ? colors.outline : null,
              fontStyle: hidden ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Стиль отдыха — только просмотр
// =======================

class _ViewLeisureSection extends StatelessWidget {
  final List<String> restPreferences;
  final String? socialFormat;
  final List<String> meetingTimePreferences;
  final String? vibe;

  const _ViewLeisureSection({
    required this.restPreferences,
    this.socialFormat,
    required this.meetingTimePreferences,
    this.vibe,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 8),
        Text(
          'Стиль отдыха',
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _ViewLeisureRow(
          title: 'Как любит отдыхать',
          selectedKeys: restPreferences,
          options: LeisureConstants.restPreferences,
        ),
        _ViewLeisureRow(
          title: 'Формат компании',
          selectedKeys: socialFormat != null ? [socialFormat!] : [],
          options: LeisureConstants.socialFormats,
        ),
        _ViewLeisureRow(
          title: 'Когда удобнее встречаться',
          selectedKeys: meetingTimePreferences,
          options: LeisureConstants.meetingTimes,
        ),
        _ViewLeisureRow(
          title: 'Вайб',
          selectedKeys: vibe != null ? [vibe!] : [],
          options: LeisureConstants.vibes,
        ),
      ],
    );
  }
}

class _ViewLeisureRow extends StatelessWidget {
  final String title;
  final List<String> selectedKeys;
  final List<LeisureOption> options;

  const _ViewLeisureRow({
    required this.title,
    required this.selectedKeys,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isEmpty = selectedKeys.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
              '—',
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
                return _LeisureChip(label: '${opt.emoji} ${opt.label}');
              }).toList(),
            ),
        ],
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
// Шторка «Фото» — read-only просмотр чужого профиля
// =======================

class _FullProfileMediaSheet extends StatefulWidget {
  final double availableHeight;
  final String targetUserId;

  const _FullProfileMediaSheet({
    required this.availableHeight,
    required this.targetUserId,
  });

  @override
  State<_FullProfileMediaSheet> createState() => _FullProfileMediaSheetState();
}

class _FullProfileMediaSheetState extends State<_FullProfileMediaSheet> {
  static const double _kCollapsedHeight = 76;
  static const Duration _kAnimDuration = Duration(milliseconds: 320);

  bool _expanded = false;
  double _dragOffsetY = 0;

  final _repo = ProfilePhotosRepositoryImpl();
  List<ProfilePhotoDto> _photos = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    try {
      final photos = await _repo.getPhotos(widget.targetUserId);
      if (!mounted) return;
      setState(() { _photos = photos; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  void _onDragUpdate(DragUpdateDetails d) {
    _dragOffsetY += d.primaryDelta ?? 0;
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

  void _openFullscreen(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhotoFullscreenViewer(photos: _photos, initialIndex: index),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final targetHeight = _expanded ? widget.availableHeight : _kCollapsedHeight;

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _kAnimDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: targetHeight,
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
              // Drag handle + title
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
                          'Фото',
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

              // Expanded content
              if (_expanded)
                Flexible(
                  fit: FlexFit.tight,
                  child: LayoutBuilder(builder: (context, constraints) {
                    if (constraints.maxHeight < 20) return const SizedBox.shrink();
                    return Column(
                      children: [
                        Divider(height: 1, thickness: 1,
                            color: colors.outline.withValues(alpha: 0.2)),
                        Expanded(child: _buildContent(colors, textTheme)),
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

  Widget _buildContent(ColorScheme colors, TextTheme textTheme) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_photos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Фото пока нет',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colors.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: _photos.length,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => _openFullscreen(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: _photos[i].publicUrl,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Center(
                        child: Icon(Icons.image_outlined,
                            color: colors.onSurface.withValues(alpha: 0.3)),
                      ),
                    ),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: colors.surfaceContainerHighest,
                      child: Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: colors.onSurface.withValues(alpha: 0.3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
        ],
      ),
    );
  }
}

// =======================
// Model: мини-карточка
// =======================

class _UserCard {
  final String userId;
  final bool miniHidden;
  final String? nickname;
  final String? avatarUrl;
  final String? name;
  final String? gender;
  final int? age;

  const _UserCard({
    required this.userId,
    required this.miniHidden,
    this.nickname,
    this.avatarUrl,
    this.name,
    this.gender,
    this.age,
  });

  factory _UserCard.fromMap(Map<String, dynamic> m) {
    return _UserCard(
      userId: m['user_id'] as String,
      miniHidden: m['mini_hidden'] as bool? ?? false,
      nickname: m['nickname'] as String?,
      avatarUrl: m['avatar_url'] as String?,
      name: m['name'] as String?,
      gender: m['gender'] as String?,
      age: m['age'] as int?,
    );
  }
}

// =======================
// Model: полный профиль
// =======================

class _FullProfile {
  final String userId;
  final bool fullProfileHidden;
  final String? nickname;
  final bool nicknameHidden;
  final String? avatarUrl;
  final bool avatarHidden;
  final String? name;
  final bool nameHidden;
  final String? gender;
  final bool genderHidden;
  final int? age;
  final bool ageHidden;
  final String? city;
  final List<String> restPreferences;
  final String? socialFormat;
  final List<String> meetingTimePreferences;
  final String? vibe;

  const _FullProfile({
    required this.userId,
    required this.fullProfileHidden,
    this.nickname,
    required this.nicknameHidden,
    this.avatarUrl,
    required this.avatarHidden,
    this.name,
    required this.nameHidden,
    this.gender,
    required this.genderHidden,
    this.age,
    required this.ageHidden,
    this.city,
    required this.restPreferences,
    this.socialFormat,
    required this.meetingTimePreferences,
    this.vibe,
  });

  factory _FullProfile.fromMap(Map<String, dynamic> m) {
    List<String> toStrList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    return _FullProfile(
      userId: m['user_id'] as String,
      fullProfileHidden: m['full_profile_hidden'] as bool? ?? false,
      nickname: m['nickname'] as String?,
      nicknameHidden: m['nickname_hidden'] as bool? ?? false,
      avatarUrl: m['avatar_url'] as String?,
      avatarHidden: m['avatar_hidden'] as bool? ?? false,
      name: m['name'] as String?,
      nameHidden: m['name_hidden'] as bool? ?? false,
      gender: m['gender'] as String?,
      genderHidden: m['gender_hidden'] as bool? ?? false,
      age: m['age'] as int?,
      ageHidden: m['age_hidden'] as bool? ?? false,
      city: m['city'] as String?,
      restPreferences: toStrList(m['rest_preferences']),
      socialFormat: m['social_format'] as String?,
      meetingTimePreferences: toStrList(m['meeting_time_preferences']),
      vibe: m['vibe'] as String?,
    );
  }
}
