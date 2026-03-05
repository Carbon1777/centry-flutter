import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import 'plan_friends_picker_sheet.dart';

/// Bottom-sheet wrapper: loads friends + server-first invite states for the current plan.
///
/// IMPORTANT:
/// - Server-first facts (invite state / membership) are on the server.
/// - Client renders canonical snapshot; optimistic state is only a short-lived UX hint.
///
/// This wrapper is tolerant to mismatched user-id sources:
/// some parts of the app may pass `app_users.id`, while other parts use `auth.user.id`.
/// We try both when needed to avoid false "Access denied" and empty friend lists.
class PlanFriendsModal extends StatefulWidget {
  /// current user id (uuid) — expected to be `public.app_users.id`
  final String appUserId;

  /// current plan id (uuid)
  final String planId;

  /// Server-first entrypoint: invite into current plan by friend's public_id.
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  /// Optional hook for parent modal/dialog (e.g. mark "didInvite" to refresh members list).
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
  late final SupabaseClient _client;
  late final FriendsRepository _friendsRepository;

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

  List<String> _userIdCandidates() {
    final primary = widget.appUserId.trim();
    final authId = _client.auth.currentUser?.id?.trim() ?? '';
    final out = <String>[];
    if (primary.isNotEmpty) out.add(primary);
    if (authId.isNotEmpty && authId != primary) out.add(authId);
    return out;
  }

  Future<void> _loadAll() async {
    if (!mounted) return;

    final planId = widget.planId.trim();
    if (planId.isEmpty) {
      setState(() => _loading = false);
      // No toast: this should not happen; keep sheet empty.
      return;
    }

    setState(() => _loading = true);

    try {
      // 1) Friends list: try candidates until we get a non-empty list (or accept empty)
      final candidates = _userIdCandidates();
      List<FriendDto> friends = const [];
      String? effectiveUserId;

      for (final id in candidates) {
        try {
          final list = await _friendsRepository.listMyFriends(appUserId: id);
          friends = list;
          effectiveUserId = id;
          if (friends.isNotEmpty) break;
        } catch (_) {
          // keep trying other ids
        }
      }

      // If we didn't manage to call repo at all, make it explicit
      effectiveUserId ??= candidates.isNotEmpty ? candidates.first : '';

      if (!mounted) return;

      // Always show friends that we could load, even if invite-state fetch fails.
      setState(() {
        _friends = friends;
      });

      // 2) Invite states: try effective id first; on "Access denied" retry with other candidate.
      Map<String, PlanFriendInviteState> states = const {};
      if (effectiveUserId.isNotEmpty) {
        states = await _fetchInviteStatesWithFallback(
          ownerUserIdPreferred: effectiveUserId,
          planId: planId,
        );
      }

      if (!mounted) return;
      setState(() {
        _inviteStatesByFriendUserId = states;
      });
    } catch (e) {
      // Fatal (friends list couldn't be loaded at all).
      if (!mounted) return;
      // Keep quiet UI; empty state will show.
      // You can re-enable a toast here if desired.
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<Map<String, PlanFriendInviteState>> _fetchInviteStatesWithFallback({
    required String ownerUserIdPreferred,
    required String planId,
  }) async {
    final candidates = <String>[ownerUserIdPreferred, ..._userIdCandidates()]
        .toSet()
        .toList();

    PostgrestException? lastAccessDenied;

    for (final id in candidates) {
      try {
        return await _fetchInviteStates(ownerUserId: id, planId: planId);
      } on PostgrestException catch (e) {
        final msg = (e.message).toString().toLowerCase();
        final details = (e.details ?? '').toString().toLowerCase();
        final code = (e.code ?? '').toString().toUpperCase();

        final isAccessDenied = code == 'P0001' &&
            (msg.contains('нет доступа') ||
                msg.contains('access denied') ||
                details.contains('нет доступа') ||
                details.contains('access denied'));

        if (isAccessDenied) {
          lastAccessDenied = e;
          // try next candidate silently
          continue;
        }
        rethrow;
      }
    }

    // If all candidates hit access denied, keep empty map (UI will still show friends).
    if (lastAccessDenied != null) {
      // silent by design
      return const {};
    }

    return const {};
  }

  Future<Map<String, PlanFriendInviteState>> _fetchInviteStates({
    required String ownerUserId,
    required String planId,
  }) async {
    final resp = await _client.rpc(
      'list_plan_friend_invite_states_v1',
      params: {
        'p_owner_user_id': ownerUserId,
        'p_plan_id': planId,
      },
    );

    final rows = (resp as List<dynamic>? ?? const []);
    final out = <String, PlanFriendInviteState>{};

    for (final r in rows) {
      if (r is! Map) continue;
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

  Future<void> _refreshInviteStatesAndNotify() async {
    widget.onInviteSent?.call();

    final planId = widget.planId.trim();
    if (planId.isEmpty) return;

    final candidates = _userIdCandidates();
    final primary = widget.appUserId.trim();
    final preferred = primary.isNotEmpty ? primary : (candidates.isNotEmpty ? candidates.first : '');
    if (preferred.isEmpty) return;

    try {
      final next = await _fetchInviteStatesWithFallback(
        ownerUserIdPreferred: preferred,
        planId: planId,
      );
      if (!mounted) return;
      setState(() => _inviteStatesByFriendUserId = next);
    } catch (_) {
      // silent
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
    // While loading, show the same sheet shell (empty list) so UI doesn't jump.
    if (_loading) {
      return PlanFriendsPickerSheet(
        friends: const [],
        onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
      );
    }

    return PlanFriendsPickerSheet(
      friends: _friends,
      inviteStatesByFriendUserId: _inviteStatesByFriendUserId,
      onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
      onAfterInvite: _refreshInviteStatesAndNotify,
    );
  }
}
