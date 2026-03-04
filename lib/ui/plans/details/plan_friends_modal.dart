import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import '../../common/center_toast.dart';
import 'plan_friends_picker_sheet.dart';

/// Wrapper for bottom-sheet:
/// - loads friends list (server-first)
/// - loads invite states for this plan (server-first, via list_plan_friend_invite_states_v1)
/// - passes everything to PlanFriendsPickerSheet which only renders UI
class PlanFriendsModal extends StatefulWidget {
  /// current app_user_id (uuid)
  final String appUserId;

  /// current plan_id (uuid). If null/empty, invite states won't be loaded (UI falls back to optimistic only).
  final String? planId;

  /// Server-first entrypoint: invite into current plan by friend's public_id
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  const PlanFriendsModal({
    super.key,
    required this.appUserId,
    required this.onInviteFriendByPublicId,
    this.planId,
  });

  @override
  State<PlanFriendsModal> createState() => _PlanFriendsModalState();
}

class _PlanFriendsModalState extends State<PlanFriendsModal> {
  late final FriendsRepository _friendsRepository;
  late final SupabaseClient _client;

  bool _loading = true;

  List<FriendDto> _friends = const [];
  Map<String, PlanFriendInviteState> _inviteStatesByFriendUserId = const {};

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _friendsRepository = FriendsRepositoryImpl(_client);
    unawaited(_loadAll());
  }

  Future<void> _loadAll() async {
    if (!mounted) return;

    final appUserId = widget.appUserId.trim();
    if (appUserId.isEmpty) {
      setState(() => _loading = false);
      await showCenterToast(
        context,
        message: 'Не удалось определить текущего пользователя',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final friends = await _friendsRepository.listMyFriends(appUserId: appUserId);
      if (!mounted) return;

      var states = <String, PlanFriendInviteState>{};

      // Load invite states only if planId is available
      final planId = (widget.planId ?? '').trim();
      if (planId.isNotEmpty) {
        states = await _fetchInviteStates(appUserId: appUserId, planId: planId);
      }

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
    final response = await _client.rpc(
      'list_plan_friend_invite_states_v1',
      params: {
        'p_owner_user_id': appUserId,
        'p_plan_id': planId,
      },
    );

    final rows = (response as List<dynamic>? ?? []);
    final out = <String, PlanFriendInviteState>{};

    for (final r in rows) {
      if (r is! Map<String, dynamic>) continue;

      final friendUserId = (r['friend_user_id'] ?? '').toString();
      if (friendUserId.isEmpty) continue;

      out[friendUserId] = PlanFriendInviteState(
        inviteState: (r['invite_state'] ?? 'NONE').toString(),
        canInvite: _asBool(r['can_invite']),
        isMember: _asBool(r['is_member']),
      );
    }

    return out;
  }

  Future<void> _refreshInviteStates() async {
    if (!mounted) return;

    final appUserId = widget.appUserId.trim();
    final planId = (widget.planId ?? '').trim();
    if (appUserId.isEmpty || planId.isEmpty) return;

    try {
      final states = await _fetchInviteStates(appUserId: appUserId, planId: planId);
      if (!mounted) return;
      setState(() {
        _inviteStatesByFriendUserId = states;
      });
    } catch (e) {
      if (!mounted) return;
      // No hard error: just toast once (optional)
      await showCenterToast(
        context,
        message: 'Ошибка обновления статусов: $e',
        isError: true,
      );
    }
  }

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final maxHeight = MediaQuery.of(context).size.height * 0.78;

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
      onAfterInvite: _refreshInviteStates,
    );
  }
}
