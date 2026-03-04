import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/center_toast.dart';

import '../../../data/friends/friend_request_result_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import '../../../data/plans/plan_details_dto.dart';
import 'details/plan_add_member_flow.dart';

class PlanMembersModal extends StatefulWidget {
  final PlanMemberDto ownerMember;
  final List<PlanMemberDto> members;

  final bool canAddMembers;

  /// Read-only view (archive/history): hide any action icons.
  final bool isReadOnly;
  final Future<void> Function(String memberAppUserId) onRemoveMember;
  final Future<String> Function() onCreateInvite;
  final Future<void> Function(String publicId) onAddByPublicId;

  final Future<PlanDetailsDto> Function()? onReloadDetails;

  const PlanMembersModal({
    super.key,
    required this.ownerMember,
    required this.members,
    required this.canAddMembers,
    this.isReadOnly = false,
    required this.onRemoveMember,
    required this.onCreateInvite,
    required this.onAddByPublicId,
    this.onReloadDetails,
  });

  @override
  State<PlanMembersModal> createState() => _PlanMembersModalState();
}

class _PlanMembersModalState extends State<PlanMembersModal> {
  late final FriendsRepository _friendsRepository;

  late PlanMemberDto _owner;
  late List<PlanMemberDto> _members;

  bool _manualRefreshing = false;
  bool _autoRefreshing = false;

  /// Local optimistic UX: we "тушим" иконку сразу после тапа.
  /// Истина всё равно на сервере; после refresh/realtime состояние должно прийти с бэка.
  final Set<String> _optimisticFriendPending = <String>{};

  /// Защита от двойного тапа/гонок
  final Set<String> _friendRequestInFlight = <String>{};

  static const Duration _kAutoRefreshInterval = Duration(seconds: 3);
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _friendsRepository = FriendsRepositoryImpl(Supabase.instance.client);

    _owner = widget.ownerMember;
    _members = List<PlanMemberDto>.from(widget.members);
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(covariant PlanMembersModal oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.ownerMember != widget.ownerMember ||
        oldWidget.members != widget.members) {
      _owner = widget.ownerMember;
      _members = List<PlanMemberDto>.from(widget.members);
      _reconcileOptimisticPendingFromCurrentSnapshot();
    }

    if (oldWidget.onReloadDetails == null && widget.onReloadDetails != null) {
      _startAutoRefresh();
    } else if (oldWidget.onReloadDetails != null &&
        widget.onReloadDetails == null) {
      _stopAutoRefresh();
    }
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }

  void _startAutoRefresh() {
    if (widget.onReloadDetails == null) return;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_kAutoRefreshInterval, (_) {
      unawaited(_refreshOnce(showError: false, showSpinner: false));
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  String _resolveMyAppUserId() {
    if (_owner.isMe == true) return _owner.appUserId;
    for (final m in _members) {
      if (m.isMe == true) return m.appUserId;
    }
    return '';
  }

  bool _sameMember(PlanMemberDto a, PlanMemberDto b) {
    // IMPORTANT: include all server-first fields that affect UI.
    return a.appUserId == b.appUserId &&
        a.publicId == b.publicId &&
        a.nickname == b.nickname &&
        a.role == b.role &&
        a.canAddFriend == b.canAddFriend &&
        a.canRemoveMember == b.canRemoveMember &&
        a.isMe == b.isMe &&
        // These fields are required for canonical "pending disabled" UX.
        // Ensure PlanMemberDto contains them (server-first snapshot fields).
        a.isFriend == b.isFriend &&
        a.hasPendingFriendRequest == b.hasPendingFriendRequest;
  }

  bool _sameMembersList(List<PlanMemberDto> a, List<PlanMemberDto> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameMember(a[i], b[i])) return false;
    }
    return true;
  }

  void _reconcileOptimisticPendingFromCurrentSnapshot() {
    if (_optimisticFriendPending.isEmpty) return;

    final byId = <String, PlanMemberDto>{};
    byId[_owner.appUserId] = _owner;
    for (final m in _members) {
      byId[m.appUserId] = m;
    }

    _optimisticFriendPending.removeWhere((appUserId) {
      final m = byId[appUserId];
      if (m == null) return true; // disappeared => cleanup
      if (m.isFriend == true) return true; // now friends => icon must disappear
      // If server says no pending anymore => re-enable (DECLINE/none)
      if (m.hasPendingFriendRequest != true) return true;
      return false;
    });
  }

  Future<void> _refreshOnce(
      {bool showError = true, bool showSpinner = true}) async {
    if (!mounted) return;
    if (widget.onReloadDetails == null) return;
    if (_manualRefreshing || _autoRefreshing) return;

    if (showSpinner) {
      setState(() => _manualRefreshing = true);
    } else {
      _autoRefreshing = true;
    }

    try {
      final details = await widget.onReloadDetails!.call();
      if (!mounted) return;

      final nextOwner = details.ownerMember ?? _owner;
      final nextMembers = List<PlanMemberDto>.from(details.members);

      final ownerChanged = !_sameMember(nextOwner, _owner);
      final membersChanged = !_sameMembersList(nextMembers, _members);

      if (ownerChanged || membersChanged) {
        setState(() {
          if (ownerChanged) _owner = nextOwner;
          if (membersChanged) _members = nextMembers;
        });
      } else {
        // still reconcile optimistic state even if lists are "same"
        _owner = nextOwner;
        _members = nextMembers;
      }

      _reconcileOptimisticPendingFromCurrentSnapshot();
    } catch (e) {
      if (!mounted) return;
      if (showError) {
        // CANON: no SnackBar. Use central toast.
        unawaited(showCenterToast(
          context,
          message: 'Ошибка обновления: $e',
          isError: true,
        ));
      }
    } finally {
      if (!mounted) return;
      if (showSpinner) {
        setState(() => _manualRefreshing = false);
      } else {
        _autoRefreshing = false;
      }
    }
  }

  bool _shouldShowAddFriend(PlanMemberDto m) {
    if (widget.isReadOnly) return false;
    if (m.isMe == true) return false;

    // Server-first: if already friends => icon must not be shown.
    if (m.isFriend == true) return false;

    // Show if canAddFriend (base visibility) OR request is pending (disabled view)
    // OR we have local optimistic pending.
    return m.canAddFriend == true ||
        m.hasPendingFriendRequest == true ||
        _optimisticFriendPending.contains(m.appUserId);
  }

  bool _isAddFriendDisabled(PlanMemberDto m) {
    if (widget.isReadOnly) return true;
    if (_friendRequestInFlight.contains(m.appUserId)) return true;

    // Server-first: pending request disables the icon.
    if (m.hasPendingFriendRequest == true) return true;

    // Local optimistic: disable immediately after tap until server confirms.
    if (_optimisticFriendPending.contains(m.appUserId)) return true;

    return false;
  }

  Future<void> _handleAddFriendPressed(PlanMemberDto target) async {
    if (!mounted) return;
    if (widget.isReadOnly) return;

    final targetPublicId = target.publicId.trim();
    if (targetPublicId.isEmpty) {
      await showCenterToast(
        context,
        message: 'Не найден public_id пользователя',
        isError: true,
      );
      return;
    }

    final myAppUserId = _resolveMyAppUserId();
    if (myAppUserId.isEmpty) {
      await showCenterToast(
        context,
        message: 'Не удалось определить текущего пользователя',
        isError: true,
      );
      return;
    }

    if (_friendRequestInFlight.contains(target.appUserId)) return;

    setState(() {
      _friendRequestInFlight.add(target.appUserId);
      _optimisticFriendPending.add(target.appUserId);
    });

    try {
      final FriendRequestResultDto r =
          await _friendsRepository.requestFriendByPublicId(
        appUserId: myAppUserId,
        targetPublicId: targetPublicId,
      );

      if (!mounted) return;

      if (r.requestStatus == 'ALREADY_FRIENDS') {
        await showCenterToast(context, message: 'Уже в друзьях');
      } else if (r.requestStatus == 'PENDING' &&
          r.requestDirection == 'OUTGOING') {
        // Каноничный центральный тост (как в friends flow).
        await showCenterToast(context, message: 'Запрос отправлен');
      } else if (r.requestStatus == 'PENDING' &&
          r.requestDirection == 'INCOMING') {
        await showCenterToast(context, message: 'Уже есть входящий запрос');
      } else {
        await showCenterToast(context, message: 'Готово');
      }
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(
        context,
        message: 'Ошибка отправки запроса: $e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _friendRequestInFlight.remove(target.appUserId);
        });
      }
      // Pull server truth ASAP (icon state must follow server snapshot)
      unawaited(_refreshOnce(showError: false, showSpinner: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.92;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Участники',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: _MemberRow(
                  member: _owner,
                  isReadOnly: widget.isReadOnly,
                  onRemoveMember: widget.onRemoveMember,
                  showAddFriend: _shouldShowAddFriend(_owner),
                  addFriendDisabled: _isAddFriendDisabled(_owner),
                  onAddFriend: () => unawaited(_handleAddFriendPressed(_owner)),
                ),
              ),
              const Divider(height: 1, thickness: 1),
              Expanded(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, index) {
                    final m = _members[index];
                    return _MemberRow(
                      member: m,
                      isReadOnly: widget.isReadOnly,
                      onRemoveMember: widget.onRemoveMember,
                      showAddFriend: _shouldShowAddFriend(m),
                      addFriendDisabled: _isAddFriendDisabled(m),
                      onAddFriend: () => unawaited(_handleAddFriendPressed(m)),
                    );
                  },
                ),
              ),
              if (widget.canAddMembers && !widget.isReadOnly) ...[
                const Divider(height: 1, thickness: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _manualRefreshing
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                barrierDismissible: true,
                                builder: (_) => PlanAddMemberModal(
                                  canInvite: widget.canAddMembers,
                                  canAddById: widget.canAddMembers,
                                  canAddFromFriends: false,
                                  onCreateInvite: widget.onCreateInvite,
                                  onAddByPublicId: widget.onAddByPublicId,
                                ),
                              );

                              if (ok == true) {
                                await _refreshOnce();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _manualRefreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Добавить участника',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final PlanMemberDto member;
  final bool isReadOnly;
  final Future<void> Function(String memberAppUserId) onRemoveMember;

  final bool showAddFriend;
  final bool addFriendDisabled;
  final VoidCallback onAddFriend;

  const _MemberRow({
    required this.member,
    required this.isReadOnly,
    required this.onRemoveMember,
    required this.showAddFriend,
    required this.addFriendDisabled,
    required this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    final isSelfParticipant = member.isMe == true && member.role != 'OWNER';

    final bg =
        isSelfParticipant ? Colors.white.withOpacity(0.06) : Colors.transparent;

    final border = isSelfParticipant
        ? Border.all(color: Colors.white.withOpacity(0.18), width: 1)
        : null;

    final nicknameWeight =
        isSelfParticipant ? FontWeight.w800 : FontWeight.w600;

    final disabledColor = Theme.of(context).disabledColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: border,
      ),
      child: Row(
        children: [
          Container(
            width: 50, // +10%
            height: 50, // +10%
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member.nickname,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: nicknameWeight,
                fontSize: 20, // +10%
              ),
            ),
          ),
          if (!isReadOnly && showAddFriend)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.person_add_alt_1,
                size: 25, // +10%
                color: addFriendDisabled ? disabledColor : null,
              ),
              onPressed: addFriendDisabled ? null : onAddFriend,
            ),
          if (!isReadOnly && member.canRemoveMember)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                color: Colors.red,
                size: 25, // +10%
              ),
              onPressed: () => onRemoveMember(member.appUserId),
            ),
        ],
      ),
    );
  }
}
