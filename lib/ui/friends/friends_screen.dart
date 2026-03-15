import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/center_toast.dart';

import '../../data/friends/friend_dto.dart';
import '../../data/friends/friend_request_result_dto.dart';
import '../../data/friends/friends_repository.dart';
import '../../features/profile/user_card_sheet.dart';
import 'widgets/add_friend_by_public_id_dialog.dart';
import 'friends_refresh_bus.dart';
import 'modals/add_friend_to_plan_modal.dart';

class FriendsScreen extends StatefulWidget {
  final String appUserId; // доменный app_users.id
  final FriendsRepository repository;

  const FriendsScreen({
    super.key,
    required this.appUserId,
    required this.repository,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  List<FriendDto> _friends = const <FriendDto>[];
  Map<String, UserMiniProfile> _profiles = {};

  RealtimeChannel? _friendshipsLowSub;
  RealtimeChannel? _friendshipsHighSub;
  RealtimeChannel? _inboxDeliveriesSub;
  RealtimeChannel? _privacySub;
  RealtimeChannel? _profilesSub;
  Timer? _refreshDebounce;
  Timer? _profilesDebounce;
  VoidCallback? _refreshBusListener;

  @override
  void initState() {
    super.initState();
    _refreshBusListener = () => _scheduleRefresh();
    FriendsRefreshBus.tick.addListener(_refreshBusListener!);
    _startRealtimeRefresh();
    _startInboxDrivenRefresh();
    _startProfilesRealtimeRefresh();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final friends = await widget.repository.listMyFriends(
        appUserId: widget.appUserId,
      );
      if (!mounted) return;

      final profiles = await loadUserMiniProfiles(
        userIds: friends.map((f) => f.friendUserId).toList(),
        context: 'friends',
      );
      if (!mounted) return;

      setState(() {
        _friends = friends;
        _profiles = profiles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _showError(context, e);
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _profilesDebounce?.cancel();
    _friendshipsLowSub?.unsubscribe();
    _friendshipsHighSub?.unsubscribe();
    _inboxDeliveriesSub?.unsubscribe();
    _privacySub?.unsubscribe();
    _profilesSub?.unsubscribe();
    if (_refreshBusListener != null) {
      FriendsRefreshBus.tick.removeListener(_refreshBusListener!);
      _refreshBusListener = null;
    }
    super.dispose();
  }

  /// Перезагружает только профили (без spinner) — вызывается по Realtime.
  void _scheduleProfilesReload() {
    _profilesDebounce?.cancel();
    _profilesDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted || _friends.isEmpty) return;
      final profiles = await loadUserMiniProfiles(
        userIds: _friends.map((f) => f.friendUserId).toList(),
        context: 'friends',
      );
      if (!mounted) return;
      setState(() => _profiles = profiles);
    });
  }

  void _startProfilesRealtimeRefresh() {
    final client = Supabase.instance.client;

    // Следим за изменениями настроек приватности любых пользователей.
    // Если изменился кто-то из друзей — перезагружаем профили.
    _privacySub = client
        .channel('friends_privacy_${widget.appUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_privacy_settings',
          callback: (payload) {
            final record = payload.newRecord as Map<String, dynamic>?
                ?? payload.oldRecord as Map<String, dynamic>?;
            if (record == null) return;
            final changedUserId = record['user_id']?.toString();
            if (changedUserId == null) return;
            if (_friends.any((f) => f.friendUserId == changedUserId)) {
              _scheduleProfilesReload();
            }
          },
        )
        .subscribe();

    // Следим за изменениями профилей (аватар, имя и т.д.).
    _profilesSub = client
        .channel('friends_user_profiles_${widget.appUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_profiles',
          callback: (payload) {
            final record = payload.newRecord as Map<String, dynamic>?
                ?? payload.oldRecord as Map<String, dynamic>?;
            if (record == null) return;
            final changedUserId = record['user_id']?.toString();
            if (changedUserId == null) return;
            if (_friends.any((f) => f.friendUserId == changedUserId)) {
              _scheduleProfilesReload();
            }
          },
        )
        .subscribe();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  void _startRealtimeRefresh() {
    final client = Supabase.instance.client;

    // Важно: фильтры без OR, поэтому подписываемся на обе стороны пары.
    _friendshipsLowSub = client
        .channel('friends_friendships_low_${widget.appUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_low_id',
            value: widget.appUserId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();

    _friendshipsHighSub = client
        .channel('friends_friendships_high_${widget.appUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_high_id',
            value: widget.appUserId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
  }

  /// Канон: список друзей на экране должен обновляться после любых
  /// каноничных уведомлений/событий, которые приходят пользователю.
  ///
  /// Даже если realtime по friendships по какой-то причине не сработал
  /// (race/visibility/channel), при получении INBOX delivery мы обязаны
  /// сделать refetch экрана.
  void _startInboxDrivenRefresh() {
    final client = Supabase.instance.client;

    _inboxDeliveriesSub = client
        .channel('friends_inbox_refresh_${widget.appUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.appUserId,
          ),
          callback: (payload) {
            try {
              final Map<String, dynamic>? record =
                  payload.newRecord as Map<String, dynamic>?;
              if (record == null) return;

              final channel = record['channel'];
              if (channel != 'INBOX') return;

              _scheduleRefresh();
            } catch (_) {}
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: () {
                unawaited(_handleAddFriendPressed(context));
              },
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Добавить в друзья'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? _buildEmptyState(context)
              : _buildList(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 44),
            const SizedBox(height: 14),
            Text(
              'Пока нет друзей',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Добавляй друзей через поиск по Public ID или список участников в планах',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: _friends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _FriendCard(
            friend: friend,
            profile: _profiles[friend.friendUserId],
            onOpenProfile: () {
              unawaited(UserCardSheet.show(
                context,
                targetUserId: friend.friendUserId,
                cardContext: 'friends',
              ));
            },
            onEditNote: () {
              unawaited(_editNote(context, friend));
            },
            onAddToPlan: () {
              unawaited(AddFriendToPlanModal.show(
                context,
                ownerAppUserId: widget.appUserId,
                friendAppUserId: friend.friendUserId,
              ));
            },
            onRemoveFriend: () {
              unawaited(_removeFriend(context, friend));
            },
          );
        },
      ),
    );
  }

  // =============================
  // Add friend by Public ID (v0)
  // =============================

  Future<void> _handleAddFriendPressed(BuildContext context) async {
    final publicId = await AddFriendByPublicIdDialog.show(context);
    if (!mounted) return;
    if (publicId == null) return;

    try {
      final FriendRequestResultDto r =
          await widget.repository.requestFriendByPublicId(
        appUserId: widget.appUserId,
        targetPublicId: publicId,
      );

      if (!mounted) return;

      if (r.requestStatus == 'ALREADY_FRIENDS') {
        await showCenterToast(
          context,
          message: 'Уже в друзьях',
        );
        return;
      }

      if (r.requestStatus == 'PENDING' && r.requestDirection == 'OUTGOING') {
        await showCenterToast(
          context,
          message: 'Запрос отправлен',
        );
        return;
      }

      if (r.requestStatus == 'PENDING' && r.requestDirection == 'INCOMING') {
        final accepted = await _confirm(
          context,
          title: 'Запрос в друзья',
          message:
              'У тебя уже есть входящий запрос от «${r.targetDisplayName}». Принять сейчас?',
          confirmText: 'Принять',
          cancelText: 'Позже',
        );
        if (!accepted) return;

        final requestId = r.requestId;
        if (requestId == null || requestId.isEmpty) {
          await _showError(context, 'request_id is missing');
          return;
        }

        await widget.repository.acceptFriendRequest(
          appUserId: widget.appUserId,
          requestId: requestId,
        );

        if (!mounted) return;

        await showCenterToast(
          context,
          message: 'Запрос принят',
        );

        await _load();
        return;
      }

      await _showInfo(
        context,
        title: 'Статус',
        message:
            'request_status=${r.requestStatus}, direction=${r.requestDirection}',
      );
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e);
    }
  }

  // =============================
  // Shared modals
  // =============================

  Future<void> _showInfo(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Ок'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required String cancelText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelText),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  Future<void> _showError(BuildContext context, Object error) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ошибка'),
          content: Text(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmRemove(BuildContext context, String displayName) async {
    final res = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить из друзей?'),
          content: Text('Удалить «$displayName» из друзей?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  // =============================
  // Note + remove
  // =============================

  Future<void> _editNote(BuildContext context, FriendDto friend) async {
    final controller = TextEditingController(text: friend.note);

    final saved = await showDialog<String?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Мой комментарий'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
            child: TextField(
              controller: controller,
              maxLength: 80,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Например: “коллега”, “сосед”, “партнёр”',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              buildCounter: (
                BuildContext context, {
                required int currentLength,
                required bool isFocused,
                required int? maxLength,
              }) {
                final max = maxLength ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$currentLength/$max',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (!mounted) return;
    if (saved == null) return;

    final trimmed = saved.trim();

    try {
      await widget.repository.upsertFriendNote(
        appUserId: widget.appUserId,
        friendUserId: friend.friendUserId,
        note: trimmed,
      );
      if (!mounted) return;

      unawaited(showCenterToast(
        context,
        message:
            trimmed.isEmpty ? 'Комментарий удалён' : 'Комментарий сохранён',
        isError: false,
      ));

      await _load();
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e);
    }
  }

  Future<void> _removeFriend(BuildContext context, FriendDto friend) async {
    final confirmed = await _confirmRemove(context, friend.displayName);
    if (!confirmed) return;

    try {
      await widget.repository.removeFriend(
        appUserId: widget.appUserId,
        friendUserId: friend.friendUserId,
      );
      if (!mounted) return;

      unawaited(showCenterToast(
        context,
        message: 'Удален из друзей',
        isError: true,
      ));

      await _load();
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e);
    }
  }
}

class _FriendCard extends StatelessWidget {
  final FriendDto friend;
  final UserMiniProfile? profile;

  final VoidCallback onOpenProfile;
  final VoidCallback onEditNote;
  final VoidCallback onAddToPlan;
  final VoidCallback onRemoveFriend;

  const _FriendCard({
    required this.friend,
    required this.profile,
    required this.onOpenProfile,
    required this.onEditNote,
    required this.onAddToPlan,
    required this.onRemoveFriend,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );

    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  UserAvatarWidget(
                    profile: profile,
                    size: 48,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ник: ${_nickLabel(profile, friend.displayName)}',
                          style: titleStyle?.copyWith(
                            color: profile?.nicknameHidden == true
                                ? Theme.of(context).colorScheme.outline
                                : null,
                            fontStyle: profile?.nicknameHidden == true
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _nameLabel(profile),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Text(
                      friend.note.isEmpty ? 'Мой комментарий…' : friend.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: friend.note.isEmpty
                          ? hintStyle
                          : Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEditNote,
                  tooltip: 'Редактировать',
                  icon: const Icon(Icons.edit, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: onRemoveFriend,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Удалить',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 238, 60, 60),
                        ),
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onAddToPlan,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Добавить в план'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _nickLabel(UserMiniProfile? profile, String fallback) {
    if (profile == null) return fallback;
    if (profile.nicknameHidden) return 'Скрыто';
    return profile.nickname ?? fallback;
  }

  static String _nameLabel(UserMiniProfile? profile) {
    if (profile == null) return 'Имя: —';
    if (profile.nameHidden) return 'Имя: Скрыто';
    final name = profile.name;
    if (name == null || name.isEmpty) return 'Имя: — Не указано';
    return 'Имя: $name';
  }
}
