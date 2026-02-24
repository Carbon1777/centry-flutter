// FIXED VERSION WITH OVERLAY BADGE (NO LAYOUT SHIFT)

import 'dart:async';

import 'plan_members_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/plans/plans_repository.dart';
import '../../data/plans/plan_details_dto.dart';

import 'widgets/plan_formatters.dart';
import 'widgets/plan_dates_block.dart';
import 'widgets/plan_places_block.dart';
import 'widgets/plan_chat_block.dart';

import '../common/center_toast.dart';

class PlanDetailsScreen extends StatefulWidget {
  final String appUserId;
  final String planId;
  final PlansRepository repository;

  const PlanDetailsScreen({
    super.key,
    required this.appUserId,
    required this.planId,
    required this.repository,
  });

  @override
  State<PlanDetailsScreen> createState() => _PlanDetailsScreenState();
}

class _PlanDetailsScreenState extends State<PlanDetailsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _actionLoading = false;
  bool _visibilityLoading = false;

  PlanDetailsDto? _details;
  String? _error;

  // ===== Live refresh (server-first snapshot) =====
  static const Duration _liveRefreshInterval = Duration(seconds: 10);
  Timer? _liveRefreshTimer;
  bool _liveRefreshInFlight = false;


  String _humanizeError(Object e) {
    if (e is PostgrestException) {
      // Server-first: server message is canonical UX text.
      return e.message;
    }
    return e.toString();
  }

  // Server-driven permission flags (client is dumb). No local fallbacks.
  bool _canEditTitle(dynamic plan) {
    try {
      return plan.canEditTitle == true;
    } catch (_) {
      return false;
    }
  }

  bool _canEditDescription(dynamic plan) {
    try {
      return plan.canEditDescription == true;
    } catch (_) {
      return false;
    }
  }

  bool _canEditDeadline(dynamic plan) {
    try {
      return plan.canEditDeadline == true;
    } catch (_) {
      return false;
    }
  }

  bool _canUpdateVisibility(dynamic plan) {
    try {
      return plan.canUpdateVisibility == true;
    } catch (_) {
      return false;
    }
  }

  bool _canDeletePlan(dynamic plan) {
    try {
      return plan.canDeletePlan == true;
    } catch (_) {
      return false;
    }
  }

  bool _canLeavePlan(dynamic plan) {
    try {
      return plan.canLeavePlan == true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _load(showSpinner: true);

    // ✅ server-first live refresh: periodically refetch canonical snapshot
    _startLiveRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopLiveRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ On resume, refresh snapshot (server remains source of truth)
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSilentlyIfPossible());
    }
  }

  void _startLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(_liveRefreshInterval, (_) {
      unawaited(_refreshSilentlyIfPossible());
    });
  }

  void _stopLiveRefresh() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = null;
  }

  Future<void> _refreshSilentlyIfPossible() async {
    if (!mounted) return;

    // Don't spam server while heavy actions are running.
    if (_loading || _actionLoading || _visibilityLoading) return;

    // Avoid overlapping requests.
    if (_liveRefreshInFlight) return;

    _liveRefreshInFlight = true;
    try {
      await _load(showSpinner: false);
    } finally {
      _liveRefreshInFlight = false;
    }
  }

  Future<void> _load({required bool showSpinner}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }

    try {
      final d = await widget.repository.getPlanDetails(
        appUserId: widget.appUserId,
        planId: widget.planId,
      );
      _details = d;
    } catch (e) {
      _details = null;
      _error = e.toString();
      debugPrint('[PlanDetailsScreen] load error: $e');
    }

    if (!mounted) return;

    if (showSpinner) {
      setState(() => _loading = false);
    } else {
      setState(() {});
    }
  }

  /// ✅ Server-first canonical reload callback for child modals (members list, etc.)
  Future<PlanDetailsDto> _reloadDetails() async {
    return await widget.repository.getPlanDetails(
      appUserId: widget.appUserId,
      planId: widget.planId,
    );
  }

  Future<void> _toggleVisibility() async {
    if (_details == null || _visibilityLoading) return;
    final plan = _details!.plan;
    if (!_canUpdateVisibility(plan)) return;

    final newValue = !_details!.plan.visibleInFeed;

    setState(() => _visibilityLoading = true);

    try {
      await widget.repository.updatePlanVisibility(
        appUserId: widget.appUserId,
        planId: widget.planId,
        visible: newValue,
      );

      await showCenterToast(context, message: newValue ? 'Видим' : 'Не видим');
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _visibilityLoading = false);
      }
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'OWNER':
        return 'Создатель';
      case 'PARTICIPANT':
        return 'Участник';
      default:
        return role;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OPEN':
        return 'Открыт';
      case 'VOTING_FINISHED':
        return 'Голосование окончено';
      case 'CLOSED':
        return 'Закрыт';
      default:
        return status;
    }
  }

  Future<void> _onPrimaryAction() async {
    if (_details == null || _actionLoading) return;

    final plan = _details!.plan;
    final canDeletePlan = _canDeletePlan(plan);
    final canLeavePlan = _canLeavePlan(plan);
    if (!canDeletePlan && !canLeavePlan) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(canDeletePlan ? 'Удалить план?' : 'Выйти из плана?'),
        content: Text(
          canDeletePlan
              ? 'План будет удалён без возможности восстановления.'
              : 'Вы перестанете участвовать в этом плане.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);

    try {
      if (canDeletePlan) {
        await widget.repository.deletePlan(
          appUserId: widget.appUserId,
          planId: widget.planId,
        );
      } else {
        await widget.repository.leavePlan(
          appUserId: widget.appUserId,
          planId: widget.planId,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _removeMember(String memberAppUserId) async {
    if (_details == null || _actionLoading) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить участника?'),
        content: const Text('Участник будет удалён из плана.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _actionLoading = true);

    try {
      await widget.repository.removeMember(
        ownerAppUserId: widget.appUserId,
        planId: widget.planId,
        memberAppUserId: memberAppUserId,
      );

      if (!mounted) return;
      await _load(showSpinner: false);

      if (!mounted) return;
      await showCenterToast(context, message: 'Участник удалён');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<String> _createInvite() async {
    if (_details == null || _actionLoading) {
      throw Exception('Plan details not loaded');
    }

    final token = await widget.repository.createInvite(
      appUserId: widget.appUserId,
      planId: widget.planId,
    );

    return token;
  }

  Future<void> _addMemberByPublicId(String publicId) async {
    if (_details == null || _actionLoading) return;

    final v = publicId.trim();
    if (v.isEmpty) return;

    setState(() => _actionLoading = true);
    try {
      await widget.repository.addMemberByPublicId(
        appUserId: widget.appUserId,
        planId: widget.planId,
        publicId: v,
      );

      if (!mounted) return;
      // ✅ CANON: internal invite by public_id does NOT add member immediately.
      // We only confirm that the invite was sent. Member list will change only
      // after invitee ACCEPTs on the server.
      await showCenterToast(context, message: 'Приглашение отправлено');
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }
Future<void> _editTitle() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditTitle(plan)) return;

    final controller = TextEditingController(text: plan.title);

    final newValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Редактировать название'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Название плана'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                final v = controller.text.trim();
                if (v.isEmpty) return;
                Navigator.of(dialogContext).pop(v);
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    if (newValue == null) return;

    final trimmed = newValue.trim();
    if (trimmed.isEmpty || trimmed == plan.title) return;

    try {
      await widget.repository.updatePlanTitle(
        appUserId: widget.appUserId,
        planId: widget.planId,
        title: trimmed,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<void> _editDescription() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditDescription(plan)) return;

    final controller = TextEditingController(text: plan.description ?? '');

    String current = controller.text.trim();
    bool canSave() => current.length >= 10;

    final newValue = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Редактировать описание'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 4,
                    onChanged: (v) {
                      setLocalState(() {
                        current = v.trim();
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Описание (минимум 10 символов)',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${current.length.clamp(0, 10)}/10',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            canSave() ? Colors.grey.shade400 : Colors.redAccent,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: canSave()
                      ? () => Navigator.of(dialogContext)
                          .pop(controller.text.trim())
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor:
                        canSave() ? const Color(0xFF3B82F6) : Colors.grey,
                  ),
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    );

    if (newValue == null) return;

    final trimmed = newValue.trim();
    if (trimmed.length < 10) return;
    if ((plan.description ?? '').trim() == trimmed) return;

    try {
      await widget.repository.updatePlanDescription(
        appUserId: widget.appUserId,
        planId: widget.planId,
        description: trimmed,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<void> _editVotingDeadline() async {
    if (_details == null) return;
    final plan = _details!.plan;
    if (!_canEditDeadline(plan)) return;

    final picked = await _pickDateTime(
      initial: plan.votingDeadlineAt,
    );

    if (picked == null) return;

    try {
      await widget.repository.updatePlanDeadline(
        appUserId: widget.appUserId,
        planId: plan.id,
        votingDeadlineAt: picked,
      );
      await _load(showSpinner: false);
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(context, message: _humanizeError(e), isError: true);
    }
  }

  Future<DateTime?> _pickDateTime({DateTime? initial}) async {
    final now = DateTime.now();
    final initialDate = (initial ?? now.add(const Duration(days: 1)));
    final safeInitialDate = initialDate.isBefore(now) ? now : initialDate;

    final date = await showDatePicker(
      context: context,
      locale: const Locale('ru'),
      initialDate: safeInitialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) return null;

    final selectedTime = await _showWheelTimePicker(
      initial: initial != null
          ? TimeOfDay(hour: initial.hour, minute: initial.minute)
          : const TimeOfDay(hour: 20, minute: 0),
    );
    if (selectedTime == null) return null;

    return DateTime(
      date.year,
      date.month,
      date.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  Future<TimeOfDay?> _showWheelTimePicker({required TimeOfDay initial}) async {
    int hour = initial.hour;
    int minute = initial.minute;

    return showDialog<TimeOfDay>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Выберите время',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: hour,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            hour = index;
                          },
                          children: List.generate(
                            24,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        ':',
                        style: TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 100,
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: minute,
                          ),
                          itemExtent: 40,
                          onSelectedItemChanged: (index) {
                            minute = index;
                          },
                          children: List.generate(
                            60,
                            (index) => Center(
                              child: Text(
                                index.toString().padLeft(2, '0'),
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(
                            dialogContext,
                            TimeOfDay(hour: hour, minute: minute),
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = _details?.plan;
    final canEditTitle = plan != null && _canEditTitle(plan);
    final canEditDescription = plan != null && _canEditDescription(plan);
    final canEditDeadline = plan != null && _canEditDeadline(plan);
    final canUpdateVisibility = plan != null && _canUpdateVisibility(plan);
    final canDeletePlan = plan != null && _canDeletePlan(plan);
    final canLeavePlan = plan != null && _canLeavePlan(plan);
    final hasPrimaryAction = canDeletePlan || canLeavePlan;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали плана'),
        actions: [
          if (!_loading && _details != null && canUpdateVisibility)
            IconButton(
              onPressed: _visibilityLoading ? null : _toggleVisibility,
              icon: Icon(
                _details!.plan.visibleInFeed
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
            ),
          if (!_loading && _details != null && hasPrimaryAction)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(
                onPressed: _actionLoading ? null : _onPrimaryAction,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(width: 1.2, color: Colors.white),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: _actionLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        canDeletePlan ? 'Удалить план' : 'Выйти из плана',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _details == null
              ? _ErrorState(
                  error: _error ?? 'Unknown error',
                  onRetry: () => _load(showSpinner: true),
                )
              : _Body(
                  details: _details!,
                  appUserId: widget.appUserId,
                  roleLabel: _roleLabel(_details!.plan.role),
                  statusLabel: _statusLabel(_details!.plan.status),
                  canEditTitle: canEditTitle,
                  canEditDescription: canEditDescription,
                  canEditDeadline: canEditDeadline,
                  onEditTitle: _editTitle,
                  onEditDescription: _editDescription,
                  onEditDeadline: _editVotingDeadline,
                  onRemoveMember: _removeMember,
                  onCreateInvite: _createInvite,
                  onAddByPublicId: _addMemberByPublicId,
                  onReloadDetails: _reloadDetails, // ✅ key line
                ),
    );
  }
}

class _Body extends StatelessWidget {
  final PlanDetailsDto details;
  final String appUserId;
  final String roleLabel;
  final String statusLabel;

  final bool canEditTitle;
  final bool canEditDescription;
  final bool canEditDeadline;
  final VoidCallback onEditTitle;
  final VoidCallback onEditDescription;
  final VoidCallback onEditDeadline;
  final Future<void> Function(String memberAppUserId) onRemoveMember;

  final Future<String> Function() onCreateInvite;
  final Future<void> Function(String publicId) onAddByPublicId;

  /// ✅ server-first: provides canonical snapshot for live modal updates
  final Future<PlanDetailsDto> Function() onReloadDetails;

  const _Body({
    required this.details,
    required this.appUserId,
    required this.roleLabel,
    required this.statusLabel,
    required this.canEditTitle,
    required this.canEditDescription,
    required this.canEditDeadline,
    required this.onEditTitle,
    required this.onEditDescription,
    required this.onEditDeadline,
    required this.onRemoveMember,
    required this.onCreateInvite,
    required this.onAddByPublicId,
    required this.onReloadDetails,
  });

  Color _roleColor(String role) =>
      role == 'OWNER' ? const Color(0xFF3B82F6) : const Color(0xFF14B8A6);

  Color _statusColor(String status) {
    switch (status) {
      case 'OPEN':
        return const Color(0xFF22C55E);
      case 'VOTING_FINISHED':
        return const Color(0xFFFACC15);
      case 'CLOSED':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey.shade400;
    }
  }

  Color _deadlineColor(DateTime? deadline) {
    if (deadline == null) return Colors.grey.shade400;
    final hours = deadline.difference(DateTime.now()).inHours;

    if (hours >= 120) return const Color(0xFF22C55E);
    if (hours >= 72) return const Color(0xFFFACC15);
    if (hours >= 24) return const Color(0xFFFB923C);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final plan = details.plan;

    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          height: 1.1,
        );

    final descValueColor = Theme.of(context).textTheme.bodyMedium?.color;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(plan.title, style: titleStyle)),
            if (canEditTitle)
              _EditPencilButton(
                onPressed: onEditTitle,
                tooltip: 'Редактировать название',
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.18)),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: Theme.of(context).textTheme.bodyMedium,
                    children: [
                      const TextSpan(
                        text: 'Описание: ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextSpan(
                        text: (plan.description ?? '').trim(),
                        style: TextStyle(color: descValueColor),
                      ),
                    ],
                  ),
                ),
              ),
              if (canEditDescription)
                _EditPencilButton(
                  onPressed: onEditDescription,
                  tooltip: 'Редактировать описание',
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _KeyValueLine(
          label: 'Роль',
          value: roleLabel,
          valueColor: _roleColor(plan.role),
        ),
        _KeyValueLine(
          label: 'Статус',
          value: statusLabel,
          valueColor: _statusColor(plan.status),
        ),
        if (plan.votingDeadlineAt != null)
          _KeyValueLine(
            label: 'Дедлайн голосования',
            value: formatPlanDateTime(plan.votingDeadlineAt),
            valueColor: _deadlineColor(plan.votingDeadlineAt),
            trailing: canEditDeadline
                ? _EditPencilButton(
                    onPressed: onEditDeadline,
                    tooltip: 'Редактировать дедлайн',
                  )
                : null,
          ),
        if (plan.eventAt != null)
          _KeyValueLine(
            label: 'Событие',
            value: formatPlanDateTime(plan.eventAt),
          ),
        const SizedBox(height: 10),
        const Divider(height: 1, thickness: 1),
        InkWell(
          onTap: () {
            if (details.ownerMember == null) return;
            showDialog(
              context: context,
              builder: (dialogContext) => PlanMembersModal(
                ownerMember: details.ownerMember!,
                members: details.members,
                canAddMembers: details.plan.canAddMembers,
                onRemoveMember: (memberAppUserId) async {
                  Navigator.of(dialogContext).pop();
                  await onRemoveMember(memberAppUserId);
                },
                onCreateInvite: () async {
                  return await onCreateInvite();
                },
                onAddByPublicId: (publicId) async {
                  await onAddByPublicId(publicId);
                },
                onReloadDetails: onReloadDetails, // ✅ live modal updates
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Участники',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Row(
                  children: [
                    Text(
                      details.plan.membersCount.toString(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, thickness: 1),
        const _SectionTitle('Голосование по датам'),
        const SizedBox(height: 6),
        PlanDatesBlock(items: details.dateCandidates),
        const SizedBox(height: 10),
        const Divider(height: 1, thickness: 1),
        const _SectionTitle('Голосование по местам'),
        const SizedBox(height: 6),
        PlanPlacesBlock(items: details.placeCandidates),
        const SizedBox(height: 10),
        const Divider(height: 1, thickness: 1),
        const _SectionTitle('Чат'),
        const SizedBox(height: 6),
        PlanChatBlock(items: details.chat),
      ],
    );
  }
}

class _EditPencilButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const _EditPencilButton({
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          icon: const Icon(Icons.edit, size: 18),
        ),
      ),
    );
  }
}

class _KeyValueLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  const _KeyValueLine({
    required this.label,
    required this.value,
    this.valueColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: valueColor),
            ),
          ),
          if (trailing != null)
            SizedBox(
              width: 40,
              height: 40,
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить план'),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}
