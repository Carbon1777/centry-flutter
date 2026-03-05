import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/plans/plan_details_dto.dart';
import 'details/plan_add_member_flow.dart';

class PlanMembersModal extends StatefulWidget {
  final String planId;
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
    required this.planId,
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
  late PlanMemberDto _owner;
  late List<PlanMemberDto> _members;

  bool _manualRefreshing = false;
  bool _autoRefreshing = false;

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
      unawaited(_refreshOnce(showSpinner: false));
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  Future<void> _refreshOnce({bool showSpinner = true}) async {
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

      setState(() {
        _owner = details.ownerMember ?? _owner;
        _members = List<PlanMemberDto>.from(details.members);
      });
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
                                  planId: widget.planId, // ✅ FIX
                                  canInvite: widget.canAddMembers,
                                  canAddById: widget.canAddMembers,
                                  canAddFromFriends: widget.canAddMembers,
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
  final bool isReadOnly;
  final Future<void> Function(String memberAppUserId) onRemoveMember;

  const _MemberRow({
    required this.member,
    required this.isReadOnly,
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
            width: 50,
            height: 50,
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
                fontSize: 20,
              ),
            ),
          ),
          if (!isReadOnly && member.canRemoveMember)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                color: Colors.red,
                size: 25,
              ),
              onPressed: () => onRemoveMember(member.appUserId),
            ),
        ],
      ),
    );
  }
}
