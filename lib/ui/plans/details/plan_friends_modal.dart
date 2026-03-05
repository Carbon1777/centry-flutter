import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import '../../common/center_toast.dart';
import 'plan_friends_picker_sheet.dart';

/// Bottom-sheet wrapper:
/// - loads friends list (server-first)
/// - loads invite states for current plan (server-first)
/// - renders PlanFriendsPickerSheet (UI-only)
class PlanFriendsModal extends StatefulWidget {
  /// current app_user_id (uuid)
  final String appUserId;

  /// current plan_id (uuid)
  final String planId;

  /// server-first entrypoint: invite into current plan by friend's public_id
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  /// optional hook: parent can mark that at least one invite was sent
  final VoidCallback? onInviteSent;

  const PlanFriendsModal({
    super.key,
    required this.appUserId,
    required this.planId,
    required this.onInviteFriendByPublicId,
    this.onInviteSent,
  });

  @override
  State<PlanFriendsModal> createState() => _PlanFriendsModalState();
}

class _PlanFriendsModalState extends State<PlanFriendsModal> {
  late final FriendsRepository _friendsRepository;

  bool _loading = true;
  List<FriendDto> _friends = const [];
  Map<String, PlanFriendInviteState> _inviteStatesByFriendUserId = const {};

  @override
  void initState() {
    super.initState();
    _friendsRepository = FriendsRepositoryImpl(Supabase.instance.client);
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    if (!mounted) return;

    final appUserId = widget.appUserId.trim();
    final planId = widget.planId.trim();

    if (appUserId.isEmpty) {
      setState(() => _loading = false);
      await showCenterToast(
        context,
        message: 'Не удалось определить текущего пользователя',
        isError: true,
      );
      return;
    }

    if (planId.isEmpty) {
      setState(() => _loading = false);
      await showCenterToast(
        context,
        message: 'Не удалось определить план',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final results = await Future.wait<dynamic>([
        _friendsRepository.listMyFriends(appUserId: appUserId),
        _fetchInviteStates(appUserId: appUserId, planId: planId),
      ]);

      final friends = results[0] as List<FriendDto>;
      final states = results[1] as Map<String, PlanFriendInviteState>;

      if (!mounted) return;
      setState(() {
        _friends = friends;
        _inviteStatesByFriendUserId = states;
      });
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(
        context,
        message: 'Ошибка загрузки: $e',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<Map<String, PlanFriendInviteState>> _fetchInviteStates({
    required String appUserId,
    required String planId,
  }) async {
    final res = await Supabase.instance.client.rpc(
      'list_plan_friend_invite_states_v1',
      params: {
        'p_owner_user_id': appUserId,
        'p_plan_id': planId,
      },
    );

    final map = <String, PlanFriendInviteState>{};
    if (res is List) {
      for (final row in res) {
        if (row is Map) {
          final friendUserId = (row['friend_user_id'] ?? '').toString();
          if (friendUserId.isEmpty) continue;

          final inviteState = (row['invite_state'] ?? 'NONE').toString();
          final canInvite = row['can_invite'] == true;
          final isMember = row['is_member'] == true;

          map[friendUserId] = PlanFriendInviteState(
            inviteState: inviteState,
            canInvite: canInvite,
            isMember: isMember,
          );
        }
      }
    }
    return map;
  }

  Future<void> _refreshInviteStates() async {
    if (!mounted) return;

    final appUserId = widget.appUserId.trim();
    final planId = widget.planId.trim();
    if (appUserId.isEmpty || planId.isEmpty) return;

    try {
      final states =
          await _fetchInviteStates(appUserId: appUserId, planId: planId);
      if (!mounted) return;
      setState(() => _inviteStatesByFriendUserId = states);
    } catch (_) {
      // do not spam errors here; server truth will be refreshed on reopen anyway
    }
  }

  Future<void> _afterInvite() async {
    widget.onInviteSent?.call();
    await _refreshInviteStates();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    if (_loading) {
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return PlanFriendsPickerSheet(
      friends: _friends,
      inviteStatesByFriendUserId: _inviteStatesByFriendUserId,
      onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
      onAfterInvite: _afterInvite,
    );
  }
}
