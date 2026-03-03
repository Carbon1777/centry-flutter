import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../common/center_toast.dart';

class AddFriendToPlanModal {
  AddFriendToPlanModal._();

  static Future<void> show(
    BuildContext context, {
    required String ownerAppUserId,
    required String friendAppUserId,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _AddFriendToPlanSheet(
          ownerAppUserId: ownerAppUserId,
          friendAppUserId: friendAppUserId,
        );
      },
    );
  }
}

class _PlanRowVm {
  final String planId;
  final String title;
  final int membersCount;
  final DateTime votingDeadlineAt;
  final String inviteState; // NONE|PENDING|DECLINED
  final bool canInvite;

  _PlanRowVm({
    required this.planId,
    required this.title,
    required this.membersCount,
    required this.votingDeadlineAt,
    required this.inviteState,
    required this.canInvite,
  });

  factory _PlanRowVm.fromJson(Map<String, dynamic> j) {
    return _PlanRowVm(
      planId: (j['plan_id'] ?? '').toString(),
      title: (j['plan_title'] ?? '').toString(),
      membersCount: (j['members_count'] as num?)?.toInt() ?? 0,
      votingDeadlineAt: DateTime.parse(j['voting_deadline_at'].toString()),
      inviteState: (j['invite_state'] ?? 'NONE').toString(),
      canInvite: (j['can_invite'] as bool?) ?? true,
    );
  }
}

class _AddFriendToPlanSheet extends StatefulWidget {
  final String ownerAppUserId;
  final String friendAppUserId;

  const _AddFriendToPlanSheet({
    required this.ownerAppUserId,
    required this.friendAppUserId,
  });

  @override
  State<_AddFriendToPlanSheet> createState() => _AddFriendToPlanSheetState();
}

class _AddFriendToPlanSheetState extends State<_AddFriendToPlanSheet> {
  bool _loading = true;
  List<_PlanRowVm> _plans = const [];
  final Set<String> _localPendingPlanIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      final res = await client.rpc(
        'list_owner_open_plans_for_friend_invite_v1',
        params: {
          'p_owner_user_id': widget.ownerAppUserId,
          'p_friend_user_id': widget.friendAppUserId,
        },
      );

      final list = (res as List<dynamic>)
          .whereType<Map>()
          .map((e) => _PlanRowVm.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _plans = list;
        _loading = false;
        _localPendingPlanIds.clear();
        for (final p in list) {
          if (p.inviteState == 'PENDING') {
            _localPendingPlanIds.add(p.planId);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showCenterToast(
        context,
        message: 'Ошибка загрузки планов',
        isError: true,
      );
    }
  }

  bool _isPending(_PlanRowVm p) {
    return _localPendingPlanIds.contains(p.planId) ||
        p.inviteState == 'PENDING';
  }

  Future<void> _inviteToPlan(_PlanRowVm p) async {
    if (_isPending(p)) return;
    if (!p.canInvite) return;

    setState(() {
      _localPendingPlanIds.add(p.planId);
    });

    try {
      final client = Supabase.instance.client;

      // Канон: никаких продуктовых решений на клиенте. Только дергаем RPC.
      // ВАЖНО: эта RPC должна на сервере использовать тот же механизм internal invites,
      // что и "invite by public_id".
      await client.rpc(
        'create_plan_internal_invite_by_user_id_v1',
        params: {
          'p_plan_id': p.planId,
          'p_inviter_app_user_id': widget.ownerAppUserId,
          'p_invitee_app_user_id': widget.friendAppUserId,
        },
      );

      if (!mounted) return;

      // Показываем только локальный статус "Отправлено приглашение" на этой карточке.
      // Invitee получит стандартный INBOX/PUSH сценарий.
      setState(() {});
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _localPendingPlanIds.remove(p.planId);
      });

      await showCenterToast(
        context,
        message: 'Не удалось отправить приглашение',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Full-width container with rounded top corners.
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            // max height ~ 90% screen
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(
              color: theme.dividerColor.withOpacity(0.22),
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
                  color: theme.dividerColor.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 12),

              // Header (fixed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Список планов',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Нажмите на план для добавления участника.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodyMedium?.color
                            ?.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              const Divider(height: 1),

              // Content (grows, scrolls)
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
                              itemBuilder: (ctx, i) {
                                final p = _plans[i];
                                final pending = _isPending(p);
                                return _PlanCard(
                                  title: p.title,
                                  membersCount: p.membersCount,
                                  votingDeadlineAt: p.votingDeadlineAt,
                                  pending: pending,
                                  onTap:
                                      pending ? null : () => _inviteToPlan(p),
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

  const _EmptyPlansState({required this.onRetry});

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
              'Показываются только ваши открытые планы, где этот участник ещё не состоит.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => unawaited(onRetry()),
              child: const Text('Обновить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final int membersCount;
  final DateTime votingDeadlineAt;
  final bool pending;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.title,
    required this.membersCount,
    required this.votingDeadlineAt,
    required this.pending,
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
          border: Border.all(color: theme.dividerColor.withOpacity(0.25)),
          color: theme.colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Открыт',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.group_outlined,
                    size: 18,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8)),
                const SizedBox(width: 8),
                Text(
                  '$membersCount участников',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Icon(Icons.schedule,
                    size: 18,
                    color: theme.textTheme.bodyMedium?.color?.withOpacity(0.8)),
                const SizedBox(width: 8),
                Text(
                  _formatDeadline(votingDeadlineAt),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (!pending) return card;

    // Disabled + overlay
    return Stack(
      children: [
        Opacity(
          opacity: 0.55,
          child: AbsorbPointer(child: card),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0xFF0D0F14).withOpacity(0.28),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2E36).withOpacity(0.85),
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
      ],
    );
  }

  static String _formatDeadline(DateTime dt) {
    // Без локали/intl: компактный формат YYYY-MM-DD HH:mm
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
