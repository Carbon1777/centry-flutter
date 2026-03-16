import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/local/user_snapshot_storage.dart';
import '../../../ui/common/center_toast.dart';

class AddPlaceToPlanResult {
  final String planId;
  final String planTitle;

  const AddPlaceToPlanResult({
    required this.planId,
    required this.planTitle,
  });
}

class AddPlaceToPlanModal {
  AddPlaceToPlanModal._();

  static Future<AddPlaceToPlanResult?> show(
    BuildContext context, {
    String? placeId,
    String? placeSubmissionId,
  }) async {
    assert(
      (placeId != null && placeSubmissionId == null) ||
          (placeId == null && placeSubmissionId != null),
      'Exactly one of placeId / placeSubmissionId must be provided',
    );

    return showModalBottomSheet<AddPlaceToPlanResult>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddPlaceToPlanSheet(
        placeId: placeId,
        placeSubmissionId: placeSubmissionId,
      ),
    );
  }
}

class _AvailablePlanVm {
  final String planId;
  final String title;
  final String role;
  final int placesCount;
  final int placesLimit;

  // Optional fields for future server expansion.
  final String? description;
  final int? membersCount;
  final DateTime? votingDeadlineAt;

  const _AvailablePlanVm({
    required this.planId,
    required this.title,
    required this.role,
    required this.placesCount,
    required this.placesLimit,
    this.description,
    this.membersCount,
    this.votingDeadlineAt,
  });

  factory _AvailablePlanVm.fromJson(Map<String, dynamic> json) {
    DateTime? deadline;
    final rawDeadline = json['voting_deadline_at'];
    if (rawDeadline != null) {
      try {
        deadline = DateTime.parse(rawDeadline.toString());
      } catch (_) {
        deadline = null;
      }
    }

    return _AvailablePlanVm(
      planId: (json['plan_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      placesCount: (json['places_count'] as num?)?.toInt() ?? 0,
      placesLimit: (json['places_limit'] as num?)?.toInt() ?? 5,
      description: json['description']?.toString(),
      membersCount: (json['members_count'] as num?)?.toInt(),
      votingDeadlineAt: deadline,
    );
  }

  String get roleLabel {
    switch (role) {
      case 'OWNER':
        return 'Создатель';
      case 'PARTICIPANT':
        return 'Участник';
      case 'GUEST':
        return 'Гость';
      default:
        return role;
    }
  }
}

class _AddPlaceToPlanSheet extends StatefulWidget {
  final String? placeId;
  final String? placeSubmissionId;

  const _AddPlaceToPlanSheet({
    required this.placeId,
    required this.placeSubmissionId,
  });

  @override
  State<_AddPlaceToPlanSheet> createState() => _AddPlaceToPlanSheetState();
}

class _AddPlaceToPlanSheetState extends State<_AddPlaceToPlanSheet>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _submittingPlanId;
  List<_AvailablePlanVm> _plans = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _load();
    }
  }

  Future<String> _resolveCurrentAppUserId() async {
    final snapshot = await UserSnapshotStorage().read();
    if (snapshot != null && snapshot.id.trim().isNotEmpty) {
      return snapshot.id;
    }

    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId == null || authUserId.isEmpty) {
      throw Exception('Пользователь не найден');
    }

    final row = await Supabase.instance.client
        .from('app_users')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    final appUserId = row?['id']?.toString();
    if (appUserId == null || appUserId.isEmpty) {
      throw Exception('Пользователь не найден');
    }

    return appUserId;
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final appUserId = await _resolveCurrentAppUserId();

      final raw = await Supabase.instance.client.rpc(
        'get_available_plans_for_place_add_v2',
        params: {
          'p_app_user_id': appUserId,
          'p_place_id': widget.placeId,
          'p_place_submission_id': widget.placeSubmissionId,
        },
      );

      final map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final items = map['items'];

      final plans = items is List
          ? items
              .whereType<Map>()
              .map((e) => _AvailablePlanVm.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList(growable: false)
          : const <_AvailablePlanVm>[];

      if (!mounted) return;

      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _plans = const [];
        _loading = false;
      });

      await showCenterToast(
        context,
        message: 'Ошибка загрузки планов',
        isError: true,
      );
    }
  }

  String _mapServerErrorToUi(String message) {
    switch (message) {
      case 'Place already added to plan':
        return 'Место уже добавлено';
      case 'Plan already has 5 places':
        return 'В плане уже 5 мест';
      case 'Plan is not open':
        return 'План закрыт';
      case 'Not a member of plan':
        return 'Нет доступа к плану';
      case 'Rejected place cannot be added to new plan':
        return 'Отклонённое место нельзя добавить в новый план';
      case 'Place not found':
        return 'Место не найдено';
      case 'Place submission not found':
        return 'Место не найдено';
      default:
        return message.isEmpty ? 'Не удалось добавить место в план' : message;
    }
  }

  Future<void> _selectPlan(_AvailablePlanVm plan) async {
    if (_submittingPlanId != null) return;

    setState(() => _submittingPlanId = plan.planId);

    try {
      final appUserId = await _resolveCurrentAppUserId();

      await Supabase.instance.client.rpc(
        'add_plan_place_v2',
        params: {
          'p_app_user_id': appUserId,
          'p_plan_id': plan.planId,
          'p_place_id': widget.placeId,
          'p_place_submission_id': widget.placeSubmissionId,
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop(
        AddPlaceToPlanResult(
          planId: plan.planId,
          planTitle: plan.title,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _submittingPlanId = null);

      final message = e is PostgrestException
          ? e.message.toString().trim()
          : e.toString().replaceFirst('Exception: ', '').trim();

      await showCenterToast(
        context,
        message: _mapServerErrorToUi(message),
        isError: true,
      );

      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                            'Выберите план',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Нажмите на план, чтобы добавить место.',
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
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _plans.isEmpty
                        ? _EmptyPlansState(onRetry: _load)
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 22),
                              itemCount: _plans.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final plan = _plans[index];
                                final submitting =
                                    _submittingPlanId == plan.planId;

                                return _PlanCard(
                                  plan: plan,
                                  submitting: submitting,
                                  onTap: submitting
                                      ? null
                                      : () => _selectPlan(plan),
                                );
                              },
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPlansState extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _EmptyPlansState({
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.playlist_add_outlined, size: 44),
            const SizedBox(height: 12),
            Text(
              'Нет доступных планов',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Нет доступных планов для добавления этого места.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _AvailablePlanVm plan;
  final bool submitting;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.plan,
    required this.submitting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
          color: theme.colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (plan.description != null && plan.description!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  plan.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              plan.roleLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (plan.membersCount != null)
                  _MetaItem(
                    icon: Icons.group_outlined,
                    text: '${plan.membersCount} участников',
                  ),
                if (plan.votingDeadlineAt != null)
                  _MetaItem(
                    icon: Icons.schedule,
                    text: _formatDateTime(plan.votingDeadlineAt!),
                  ),
                _MetaItem(
                  icon: Icons.place_outlined,
                  text: '${plan.placesCount}/${plan.placesLimit} мест',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!submitting) return card;

    return Stack(
      children: [
        Opacity(opacity: 0.55, child: AbsorbPointer(child: card)),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0D0F14).withValues(alpha: 0.28),
            ),
          ),
        ),
        const Positioned.fill(
          child: Center(
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString().padLeft(4, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaItem({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
