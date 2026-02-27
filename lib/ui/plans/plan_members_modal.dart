import 'dart:async';

import 'package:flutter/material.dart';
import '../../../data/plans/plan_details_dto.dart';
import 'details/plan_add_member_flow.dart';

class PlanMembersModal extends StatefulWidget {
  final PlanMemberDto ownerMember;
  final List<PlanMemberDto> members;

  final bool canAddMembers;
  final Future<void> Function(String memberAppUserId) onRemoveMember;
  final Future<String> Function() onCreateInvite;
  final Future<void> Function(String publicId) onAddByPublicId;

  final Future<PlanDetailsDto> Function()? onReloadDetails;

  const PlanMembersModal({
    super.key,
    required this.ownerMember,
    required this.members,
    required this.canAddMembers,
    required this.onRemoveMember,
    required this.onCreateInvite,
    required this.onAddByPublicId,
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

  // Auto-refresh while the modal is open to reflect server-side membership changes
  // (e.g. someone accepted an invite) without requiring the user to reopen the modal.
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
    }

    // Start/stop auto-refresh depending on whether reload callback is available.
    if (oldWidget.onReloadDetails == null && widget.onReloadDetails != null) {
      _startAutoRefresh();
    } else if (oldWidget.onReloadDetails != null && widget.onReloadDetails == null) {
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
      // Silent refresh: no snackbars on background polling.
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

  Future<void> _refreshOnce({bool showError = true, bool showSpinner = true}) async {
    if (!mounted) return;
    if (widget.onReloadDetails == null) return;

    // Prevent overlapping refreshes (manual/auto).
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

      // Avoid unnecessary rebuilds if nothing changed.
      final ownerChanged = !_sameMember(nextOwner, _owner);
      final membersChanged = !_sameMembersList(nextMembers, _members);

      if (ownerChanged || membersChanged) {
        setState(() {
          if (ownerChanged) _owner = nextOwner;
          if (membersChanged) _members = nextMembers;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления: $e')),
        );
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
                  onRemoveMember: widget.onRemoveMember,
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
                      onRemoveMember: widget.onRemoveMember,
                    );
                  },
                ),
              ),
              if (widget.canAddMembers) ...[
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

                              // ✅ refresh only when something was actually added
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
  final Future<void> Function(String memberAppUserId) onRemoveMember;

  const _MemberRow({
    required this.member,
    required this.onRemoveMember,
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    member.nickname,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: nicknameWeight, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '•  ID',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    member.publicId,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (member.canAddFriend)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.person_add_alt_1, size: 20),
              onPressed: () {},
            ),
          if (member.canRemoveMember)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              onPressed: () => onRemoveMember(member.appUserId),
            ),
        ],
      ),
    );
  }
}
