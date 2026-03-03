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

class _AddFriendToPlanSheetState extends State<_AddFriendToPlanSheet>
    with WidgetsBindingObserver {
  bool _loading = true;
  List<_PlanRowVm> _plans = const [];
  final Set<String> _localPendingPlanIds = <String>{};

  RealtimeChannel? _membersSub;
  RealtimeChannel? _invitesSub;
  RealtimeChannel? _inboxSub;

  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    _startRealtimeAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshDebounce?.cancel();
    _membersSub?.unsubscribe();
    _invitesSub?.unsubscribe();
    _inboxSub?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ Canon: PUSH is a "budilnik". On resume (tap from background/cold),
    // we must refetch server truth (INBOX/RPC), not rely on realtime inserts.
    if (state == AppLifecycleState.resumed) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  void _startRealtimeAutoRefresh() {
    final client = Supabase.instance.client;

    // ✅ Канон: для owner самый надёжный триггер обновления — INBOX (источник истины).
    // При ACCEPT/LEAVE/REMOVE сервер шлёт owner'у INBOX события — ловим и делаем refetch.
    _inboxSub = client
        .channel('friends_add_to_plan_inbox_${widget.ownerAppUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notification_deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.ownerAppUserId,
          ),
          callback: (payload) {
            try {
              final Map<String, dynamic>? record =
                  payload.newRecord as Map<String, dynamic>?;
              if (record == null) return;

              // Рефреш только по INBOX.
              final channel = record['channel'];
              if (channel != 'INBOX') return;

              _scheduleRefresh();
            } catch (_) {
              // Не крэшим UI.
            }
          },
        )
        .subscribe();

    // (Дополнительно, если realtime по таблицам работает) —
    // изменения членства/инвайтов для invitee тоже могут триггерить refresh.
    _membersSub = client
        .channel('friends_add_to_plan_members_${widget.friendAppUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'core_plan_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'app_user_id',
            value: widget.friendAppUserId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();

    _invitesSub = client
        .channel('friends_add_to_plan_invites_${widget.friendAppUserId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'plan_internal_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'invitee_app_user_id',
            value: widget.friendAppUserId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
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

        _localPendingPlanIds
          ..clear()
          ..addAll(
            list.where((p) => p.inviteState == 'PENDING').map((p) => p.planId),
          );
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

      await client.rpc(
        'create_plan_internal_invite_by_user_id_v1',
        params: {
          'p_inviter_app_user_id': widget.ownerAppUserId,
          'p_plan_id': p.planId,
          'p_invitee_app_user_id': widget.friendAppUserId,
        },
      );

      if (!mounted) return;

      // Сервер пошлёт INBOX/PUSH, а INBOX-sub тут же дернёт refresh.
      _scheduleRefresh();
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
        Positioned.fill(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2E36).withOpacity(0.9),
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
        ),
      ],
    );
  }

  static String _formatDeadline(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }
}
