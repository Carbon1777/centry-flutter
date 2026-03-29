import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../features/profile/user_card_sheet.dart';
import '../../common/center_toast.dart';

/// Server-first invite state for a friend relative to a plan.
/// Values are produced by `list_plan_friend_invite_states_v1`.
class PlanFriendInviteState {
  /// 'NONE' | 'PENDING' | 'DECLINED'
  final String inviteState;

  /// Server-first: whether owner can invite right now.
  final bool canInvite;

  /// Server-first: friend is already a member of the plan.
  final bool isMember;

  const PlanFriendInviteState({
    required this.inviteState,
    required this.canInvite,
    required this.isMember,
  });

  static const none = PlanFriendInviteState(
    inviteState: 'NONE',
    canInvite: true,
    isMember: false,
  );

  bool get isPending => inviteState == 'PENDING';
}

/// Bottom sheet UI: выбор друга для приглашения в план.
class PlanFriendsPickerSheet extends StatefulWidget {
  final List<FriendDto> friends;

  final Map<String, PlanFriendInviteState> inviteStatesByFriendUserId;

  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  final Future<void> Function()? onAfterInvite;

  const PlanFriendsPickerSheet({
    super.key,
    required this.friends,
    required this.onInviteFriendByPublicId,
    this.inviteStatesByFriendUserId = const {},
    this.onAfterInvite,
  });

  @override
  State<PlanFriendsPickerSheet> createState() => _PlanFriendsPickerSheetState();
}

class _PlanFriendsPickerSheetState extends State<PlanFriendsPickerSheet> {
  final Set<String> _pendingOptimistic = <String>{};
  final Set<String> _inFlight = <String>{};

  Map<String, UserMiniProfile> _profiles = {};

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final ids = widget.friends.map((f) => f.friendUserId).toList();
    if (ids.isEmpty) return;
    final profiles = await loadUserMiniProfiles(
      userIds: ids,
      context: 'friends',
    );
    if (mounted) setState(() => _profiles = profiles);
  }

  PlanFriendInviteState _stateFor(FriendDto f) =>
      widget.inviteStatesByFriendUserId[f.friendUserId] ??
      PlanFriendInviteState.none;

  bool _isDisabled(FriendDto f) {
    final s = _stateFor(f);
    if (s.isMember) return true;
    if (s.isPending) return true;
    if (!s.canInvite) return true;
    return _pendingOptimistic.contains(f.friendUserId) ||
        _inFlight.contains(f.friendUserId);
  }

  bool _showPendingOverlay(FriendDto f) {
    final s = _stateFor(f);
    return s.isPending || _pendingOptimistic.contains(f.friendUserId);
  }

  Future<void> _invite(FriendDto f) async {
    if (!mounted) return;

    final s = _stateFor(f);
    if (s.isMember || s.isPending || !s.canInvite) return;
    if (_inFlight.contains(f.friendUserId)) return;

    final publicId = f.publicId.trim();
    if (publicId.isEmpty) {
      unawaited(
        showCenterToast(
          context,
          message: 'Не найден public_id друга',
          isError: true,
        ),
      );
      return;
    }

    setState(() {
      _inFlight.add(f.friendUserId);
      _pendingOptimistic.add(f.friendUserId);
    });

    try {
      await widget.onInviteFriendByPublicId(publicId);
      if (!mounted) return;

      if (widget.onAfterInvite != null) {
        unawaited(widget.onAfterInvite!.call());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingOptimistic.remove(f.friendUserId));
      if (e is PostgrestException && e.message.contains('BLOCKED')) {
        unawaited(showCenterToast(context,
            message: 'Коммуникация невозможна — действует блокировка',
            isError: true));
      }
    } finally {
      if (mounted) setState(() => _inFlight.remove(f.friendUserId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final visibleFriends = widget.friends.where((f) {
      final s = _stateFor(f);
      return !s.isMember;
    }).toList();

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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Список друзей',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Выберите друга для добавления в план.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
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
              Expanded(
                child: visibleFriends.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                        physics: const ClampingScrollPhysics(),
                        itemCount: visibleFriends.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) {
                          final f = visibleFriends[index];
                          return _FriendCard(
                            friend: f,
                            profile: _profiles[f.friendUserId],
                            pending: _showPendingOverlay(f),
                            enabled: !_isDisabled(f),
                            onTap: () => unawaited(_invite(f)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
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
              'Нет друзей для добавления в этот план',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Нет кандидатов для добавления из списка друзей. Либо у вас нет друзей, либо они все уже находятся в числе участников этого плана',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final FriendDto friend;
  final UserMiniProfile? profile;
  final bool pending;
  final bool enabled;
  final VoidCallback onTap;

  const _FriendCard({
    required this.friend,
    required this.profile,
    required this.pending,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Никнейм: из профиля, fallback — displayName
    final String nickDisplay;
    final n = profile?.nickname?.trim() ?? friend.displayName.trim();
    nickDisplay = n.isEmpty ? '—' : n;

    // Имя: из профиля
    final String nameDisplay;
    final nm = profile?.name?.trim() ?? '';
    nameDisplay = nm.isEmpty ? '—' : nm;

    final note = friend.note.trim();
    final borderColor = theme.dividerColor.withValues(alpha: 0.25);
    final noteBg = theme.dividerColor.withValues(alpha: 0.10);

    final nickStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800);

    final nameStyle = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);

    final base = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatarWidget(
              profile: profile,
              size: 46,
              borderRadius: const BorderRadius.all(Radius.circular(14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ник: $nickDisplay',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nickStyle,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Имя: $nameDisplay',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: noteBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      note.isEmpty ? 'Мой комментарий...' : note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: note.isEmpty
                            ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.35)
                            : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!pending) return base;

    return Stack(
      children: [
        Opacity(opacity: 0.55, child: AbsorbPointer(child: base)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0D0F14).withValues(alpha: 0.28),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E36).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF3A3F49)),
              ),
              child: Text(
                'Отправлено приглашение',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
