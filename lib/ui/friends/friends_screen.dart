import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/center_toast.dart';

import '../../data/friends/friend_dto.dart';
import '../../data/friends/friend_request_result_dto.dart';
import '../../data/friends/friends_repository.dart';
import '../../data/attention_signs/attention_signs_repository_impl.dart';
import '../../data/blocks/blocks_repository_impl.dart';
import '../../data/private_chats/private_chats_repository_impl.dart';
import '../../features/profile/user_card_sheet.dart';
import '../private_chats/private_chat_screen.dart';
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
  // canCreate[friendUserId] == true → кнопка «Создать чат» видна
  Map<String, bool> _canCreateChat = {};
  late final _privateChatsRepo =
      PrivateChatsRepositoryImpl(Supabase.instance.client);
  late final _blocksRepo = BlocksRepositoryImpl(Supabase.instance.client);
  late final _attentionSignsRepo =
      AttentionSignsRepositoryImpl(Supabase.instance.client);

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

      final ids = friends.map((f) => f.friendUserId).toList();

      final results = await Future.wait([
        loadUserMiniProfiles(userIds: ids, context: 'friends'),
        // Параллельно проверяем canCreateChat для каждого друга
        Future.wait(ids.map((id) => _privateChatsRepo
            .canCreatePrivateChat(appUserId: widget.appUserId, partnerId: id)
            .then((r) => MapEntry(id, r.canCreate))
            .catchError((_) => MapEntry(id, false)))),
      ]);
      if (!mounted) return;

      final profiles = results[0] as Map<String, UserMiniProfile>;
      final canCreateEntries =
          (results[1] as List<MapEntry<String, bool>>);
      final canCreate = Map<String, bool>.fromEntries(canCreateEntries);

      setState(() {
        _friends = friends;
        _profiles = profiles;
        _canCreateChat = canCreate;
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
        physics: const ClampingScrollPhysics(),
        itemCount: _friends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _FriendCard(
            friend: friend,
            profile: _profiles[friend.friendUserId],
            canCreateChat: _canCreateChat[friend.friendUserId] ?? false,
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
            onCreateChat: () {
              unawaited(_createChat(context, friend));
            },
            onBlock: () {
              unawaited(_blockFriend(context, friend));
            },
            onSendAttentionSign: () {
              unawaited(_handleSendAttentionSign(context, friend));
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
        if (!mounted) return;
        // ignore: use_build_context_synchronously — guarded above, exclusive branch
        await showCenterToast(context, message: 'Уже в друзьях');
        return;
      }

      if (r.requestStatus == 'PENDING' && r.requestDirection == 'OUTGOING') {
        if (!mounted) return;
        // ignore: use_build_context_synchronously — guarded above, exclusive branch
        await showCenterToast(context, message: 'Запрос отправлен');
        return;
      }

      if (r.requestStatus == 'PENDING' && r.requestDirection == 'INCOMING') {
        if (!mounted) return;
        final accepted = await _confirm(
          context, // ignore: use_build_context_synchronously
          title: 'Запрос в друзья',
          message:
              'У тебя уже есть входящий запрос от «${r.targetDisplayName}». Принять сейчас?',
          confirmText: 'Принять',
          cancelText: 'Позже',
        );
        if (!accepted) return;
        if (!mounted) return;

        final requestId = r.requestId;
        if (requestId == null || requestId.isEmpty) {
          // ignore: use_build_context_synchronously — guarded by mounted check above
          await _showError(context, 'request_id is missing');
          return;
        }

        await widget.repository.acceptFriendRequest(
          appUserId: widget.appUserId,
          requestId: requestId,
        );

        if (!mounted) return;
        // ignore: use_build_context_synchronously — guarded above
        await showCenterToast(context, message: 'Запрос принят');

        await _load();
        return;
      }

      if (!mounted) return;
      await _showInfo(
        context, // ignore: use_build_context_synchronously
        title: 'Статус',
        message:
            'request_status=${r.requestStatus}, direction=${r.requestDirection}',
      );
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e); // ignore: use_build_context_synchronously
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

      await showCenterToast(
        context, // ignore: use_build_context_synchronously
        message:
            trimmed.isEmpty ? 'Комментарий удалён' : 'Комментарий сохранён',
        isError: false,
      );

      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e); // ignore: use_build_context_synchronously
    }
  }

  Future<void> _createChat(BuildContext context, FriendDto friend) async {
    final nick = _profiles[friend.friendUserId]?.nickname ?? friend.displayName;
    final confirmed = await _confirm(
      context,
      title: 'Создать чат',
      message: 'Создать чат с пользователем «$nick»?',
      confirmText: 'Создать',
      cancelText: 'Отмена',
    );
    if (!confirmed || !context.mounted) return;

    try {
      final result = await _privateChatsRepo.createPrivateChat(
        appUserId: widget.appUserId,
        partnerId: friend.friendUserId,
      );
      if (!context.mounted) return;

      if (!result.isSuccess) {
        await _showError(context, result.error ?? 'Ошибка создания чата');
        return;
      }

      final profile = _profiles[friend.friendUserId];
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          appUserId: widget.appUserId,
          chatId: result.chatId!,
          partnerUserId: friend.friendUserId,
          partnerProfile: profile,
        ),
      ));
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      await _showError(context, e);
    }
  }

  Future<void> _blockFriend(BuildContext context, FriendDto friend) async {
    final nick = _profiles[friend.friendUserId]?.nickname ?? friend.displayName;
    final confirmed = await _confirm(
      context,
      title: 'Заблокировать',
      message: 'Заблокировать «$nick»? Дружба будет разорвана.',
      confirmText: 'Заблокировать',
      cancelText: 'Отмена',
    );
    if (!confirmed || !context.mounted) return;

    try {
      final result = await _blocksRepo.blockUser(
        appUserId: widget.appUserId,
        targetUserId: friend.friendUserId,
      );
      if (!context.mounted) return;

      if (result.isSuccess) {
        await showCenterToast(context, message: 'Пользователь заблокирован');
        if (!mounted) return;
        await _load();
      }
    } catch (e) {
      if (!context.mounted) return;
      await _showError(context, e);
    }
  }

  Future<void> _removeFriend(BuildContext context, FriendDto friend) async {
    final confirmed = await _confirmRemove(context, friend.displayName);
    if (!confirmed) return;
    if (!context.mounted) return;

    try {
      await widget.repository.removeFriend(
        appUserId: widget.appUserId,
        friendUserId: friend.friendUserId,
      );
      if (!context.mounted) return;

      await showCenterToast(
        context,
        message: 'Удален из друзей',
        isError: true,
      );

      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!context.mounted) return;
      await _showError(context, e);
    }
  }

  Future<void> _handleSendAttentionSign(
      BuildContext context, FriendDto friend) async {
    final nick = friend.displayName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Знак внимания'),
        content: Text(
            'Вы действительно хотите отправить знак внимания пользователю «$nick»?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final box =
          await _attentionSignsRepo.getMyBox(appUserId: widget.appUserId);
      if (!context.mounted) return;
      final mySign = box.mySign;
      if (mySign == null) {
        await showCenterToast(
          context,
          message: 'Сегодня знаков не осталось. Ждите следующий знак.',
          isError: true,
        );
        return;
      }
      final result = await _attentionSignsRepo.sendSign(
        appUserId: widget.appUserId,
        targetUserId: friend.friendUserId,
        dailySignId: mySign.dailySignId,
      );
      if (!context.mounted) return;
      if (result.isSuccess) {
        await showCenterToast(context, message: 'Знак внимания отправлен');
      } else {
        await showCenterToast(
          context,
          message: result.error ?? 'Не удалось отправить знак',
          isError: true,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      await showCenterToast(context, message: 'Ошибка: $e', isError: true);
    }
  }
}

class _FriendCard extends StatelessWidget {
  final FriendDto friend;
  final UserMiniProfile? profile;
  final bool canCreateChat;

  final VoidCallback onOpenProfile;
  final VoidCallback onEditNote;
  final VoidCallback onAddToPlan;
  final VoidCallback onRemoveFriend;
  final VoidCallback onCreateChat;
  final VoidCallback onBlock;
  final VoidCallback onSendAttentionSign;

  const _FriendCard({
    required this.friend,
    required this.profile,
    required this.canCreateChat,
    required this.onOpenProfile,
    required this.onEditNote,
    required this.onAddToPlan,
    required this.onRemoveFriend,
    required this.onCreateChat,
    required this.onBlock,
    required this.onSendAttentionSign,
  });

  void _showActionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF252D3D), Color(0xFF181E2B)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              _FriendActionTile(
                icon: Icons.event_outlined,
                iconColor: const Color(0xFF7FB0FF),
                label: 'Добавить в план',
                labelColor: Colors.white,
                onTap: () {
                  Navigator.of(context).pop();
                  onAddToPlan();
                },
              ),
              _friendActionDivider(),
              if (canCreateChat) ...[
                _FriendActionTile(
                  icon: Icons.chat_bubble_outline,
                  iconColor: Colors.white.withValues(alpha: 0.80),
                  label: 'Создать чат',
                  labelColor: Colors.white,
                  onTap: () {
                    Navigator.of(context).pop();
                    onCreateChat();
                  },
                ),
                _friendActionDivider(),
              ],
              _FriendActionTile(
                icon: Icons.person_remove_outlined,
                iconColor: const Color(0xFFFF445A),
                label: 'Удалить из друзей',
                labelColor: const Color(0xFFFF445A),
                onTap: () {
                  Navigator.of(context).pop();
                  onRemoveFriend();
                },
              ),
              _friendActionDivider(),
              _FriendActionTile(
                icon: Icons.block,
                iconColor: const Color(0xFFFF445A),
                label: 'Заблокировать',
                labelColor: const Color(0xFFFF445A),
                onTap: () {
                  Navigator.of(context).pop();
                  onBlock();
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _friendActionDivider() => Divider(
        height: 1,
        thickness: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.white.withValues(alpha: 0.07),
      );

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );

    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.8),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: IntrinsicWidth(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: InkWell(
                      onTap: onOpenProfile,
                      onLongPress: onSendAttentionSign,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserAvatarWidget(
                              profile: profile,
                              size: 48,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Ник: ${_nickLabel(profile, friend.displayName)}',
                                  style: titleStyle,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _nameLabel(profile),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.chevron_right,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showActionsSheet(context),
                icon: const Icon(Icons.more_horiz, size: 18),
                label: const Text('Меню'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
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
        ],
      ),
    );
  }

  static String _nickLabel(UserMiniProfile? profile, String fallback) {
    if (profile == null) return fallback;
    return profile.nickname ?? fallback;
  }

  static String _nameLabel(UserMiniProfile? profile) {
    if (profile == null) return 'Имя: —';
    final name = profile.name;
    if (name == null || name.isEmpty) return 'Имя: — Не указано';
    return 'Имя: $name';
  }
}

class _FriendActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _FriendActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
