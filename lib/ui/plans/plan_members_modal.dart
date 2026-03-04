import 'dart:async';

import 'package:flutter/material.dart';
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

  /// Second entry-point into existing friends flow: send friend request to this member.
  /// Server-first: caller must invoke the canonical RPC already used by "add friend by ID".
  ///
  /// If null, the icon is still rendered but tap does nothing.
  final Future<void> Function({
    required String targetPublicId,
    required String targetAppUserId,
  })? onAddFriend;

  /// Canonical central toast "Приглашение отправлено" (same component/text as add-by-ID flow).
  final VoidCallback? onShowFriendInviteSentToast;

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
    this.onAddFriend,
    this.onShowFriendInviteSentToast,
    this.onReloadDetails,
  });

  @override
  State<PlanMembersModal> createState() => _PlanMembersModalState();
}

class _PlanMembersModalState extends State<PlanMembersModal> {
  late PlanMemberDto _owner;
  late List<PlanMemberDto> _members;

  bool _manualRefreshing = false;
  bool _autoRefreshing = false;

  /// Local optimistic state: immediately disable the add-friend icon after tap.
  /// Cleared when server snapshot indicates user can add again (declined) or icon disappears (friend).
  final Set<String> _optimisticFriendRequests = <String>{};

  static const Duration _kAutoRefreshInterval = Duration(seconds: 3);
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
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
      _reconcileOptimisticFriendRequestsWithServer();
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

  Future<void> _sendFriendRequestForMember(PlanMemberDto member) async {
    if (!mounted) return;

    // Guard: if caller didn't wire the existing friends-RPC yet, we do nothing.
    final fn = widget.onAddFriend;
    if (fn == null) return;

    // We must have a publicId for the existing friends flow.
    if (member.publicId.isEmpty) return;

    // Avoid duplicate taps / races.
    if (_optimisticFriendRequests.contains(member.appUserId)) return;

    setState(() => _optimisticFriendRequests.add(member.appUserId));

    try {
      await fn(
        targetPublicId: member.publicId,
        targetAppUserId: member.appUserId,
      );

      if (!mounted) return;
      widget.onShowFriendInviteSentToast?.call();

      // Pull latest server snapshot ASAP (without spinner).
      unawaited(_refreshOnce(showError: false, showSpinner: false));
    } catch (_) {
      // If RPC failed, revert optimistic disabled state.
      if (!mounted) return;
      setState(() => _optimisticFriendRequests.remove(member.appUserId));
      rethrow;
    }
  }

  void _reconcileOptimisticFriendRequestsWithServer() {
    // If server says we can add friend again => request declined / cleared => re-enable.
    // If member disappeared (removed from list) => clear.
    // If member became a friend, current DTO should already render without the icon
    // (server should set canAddFriend=false for friends and the icon will not render).
    _optimisticFriendRequests.removeWhere((appUserId) {
      PlanMemberDto? member;
      if (appUserId == _owner.appUserId) {
        member = _owner;
      } else {
        for (final m in _members) {
          if (m.appUserId == appUserId) {
            member = m;
            break;
          }
        }
      }

      if (member == null) return true;
      if (member.canAddFriend) return true;
      return false;
    });
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

  bool _sameMember(PlanMemberDto a, PlanMemberDto b) {
    return a.appUserId == b.appUserId &&
        a.publicId == b.publicId &&
        a.nickname == b.nickname &&
        a.role == b.role;
  }

  bool _sameMembersList(List<PlanMemberDto> a, List<PlanMemberDto> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameMember(a[i], b[i])) return false;
    }
    return true;
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
          _reconcileOptimisticFriendRequestsWithServer();
        });
      } else {
        // Even if nothing changed, server might have flipped request state.
        _reconcileOptimisticFriendRequestsWithServer();
      }
    } catch (e) {
      if (!mounted) return;
      if (showError) {
        // Канон: никакие SnackBar. Ошибку обновления молча игнорируем (UI подтянется на следующем тике).
        debugPrint('PlanMembersModal: refresh failed: $e');
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
                  onAddFriend: _sendFriendRequestForMember,
                  isAddFriendOptimisticallyDisabled:
                      _optimisticFriendRequests.contains(_owner.appUserId),
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
                      onAddFriend: _sendFriendRequestForMember,
                      isAddFriendOptimisticallyDisabled:
                          _optimisticFriendRequests.contains(m.appUserId),
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

  /// Called to send friend request via existing friends flow (RPC is owned by caller via PlanMembersModal.onAddFriend).
  final Future<void> Function(PlanMemberDto member)? onAddFriend;

  /// Optimistic local disabled state: immediately grey out after tap.
  final bool isAddFriendOptimisticallyDisabled;

  const _MemberRow({
    required this.member,
    required this.isReadOnly,
    required this.onRemoveMember,
    required this.onAddFriend,
    required this.isAddFriendOptimisticallyDisabled,
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
          if (!isReadOnly &&
              (member.canAddFriend || isAddFriendOptimisticallyDisabled))
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.person_add_alt_1,
                size: 25, // +10%
                color: (member.canAddFriend &&
                        !isAddFriendOptimisticallyDisabled &&
                        onAddFriend != null)
                    ? null
                    : Colors.white.withOpacity(0.35),
              ),
              onPressed: (member.canAddFriend &&
                      !isAddFriendOptimisticallyDisabled &&
                      onAddFriend != null)
                  ? () => onAddFriend!.call(member)
                  : null,
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
