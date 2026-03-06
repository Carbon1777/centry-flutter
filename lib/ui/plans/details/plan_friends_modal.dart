import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import 'plan_friends_picker_sheet.dart';

/// Bottom-sheet wrapper: loads friends + server-first invite states for the current plan.
///
/// Канон:
/// - Все продуктовые факты (is_member / invite_state / can_invite) — на сервере.
/// - Клиент рендерит каноничный снапшот.
/// - Автообновление делаем по server-first событию: delivery для owner'а,
///   которое сервер вставляет на ACCEPT/DECLINE (notification_deliveries).
class PlanFriendsModal extends StatefulWidget {
  /// current user id (uuid) — каноничный user_id, используемый в планах и friends.
  final String appUserId;

  /// current plan id (uuid)
  final String planId;

  /// Server-first entrypoint: invite into current plan by friend's public_id.
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  /// Optional hook for parent modal/dialog:
  /// если мы отправили хотя бы одно приглашение — можно закрыть родителя и обновить участников.
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
  static const Duration _kRefreshDebounce = Duration(milliseconds: 250);

  /// Временный флаг для диагностики auto-refresh.
  /// В release (kDebugMode=false) логи не печатаются.
  static const bool _kDebugRealtimeLogs = true;

  late final SupabaseClient _client;
  late final FriendsRepository _friendsRepository;

  RealtimeChannel? _channel;

  bool _loading = true;
  List<FriendDto> _friends = const [];
  Map<String, PlanFriendInviteState> _inviteStatesByFriendUserId = const {};

  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _queuedNotifyParent = false;
  bool _queuedFromRealtime = false;
  String? _queuedReason;

  Timer? _refreshDebounce;

  /// Key epoch for PlanFriendsPickerSheet.
  /// We bump this only when refresh is triggered by server-first realtime event,
  /// to reset optimistic UI state in the sheet (without adding “logic” into the sheet).
  int _sheetEpoch = 0;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _friendsRepository = FriendsRepositoryImpl(_client);

    _startRealtime();
    unawaited(_loadAll());
  }

  @override
  void didUpdateWidget(covariant PlanFriendsModal oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Safety: if parent rebuilt modal with different plan/user — restart channel + reload snapshot.
    if (oldWidget.appUserId != widget.appUserId ||
        oldWidget.planId != widget.planId) {
      _stopRealtime();
      _startRealtime();
      unawaited(_loadAll());
    }
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _refreshDebounce = null;

    _stopRealtime();
    super.dispose();
  }

  void _stopRealtime() {
    final ch = _channel;
    if (ch != null) {
      _client.removeChannel(ch);
      _channel = null;
    }
  }

  void _startRealtime() {
    final userId = widget.appUserId.trim();
    final planId = widget.planId.trim();
    if (userId.isEmpty || planId.isEmpty) return;

    // Note: channel name must be stable for this modal instance to avoid duplicates.
    final channelName = 'plan_friends_modal_${planId}_$userId';
    _channel = _client.channel(channelName);

    void onChange(dynamic payload, String changeEvent) {
      // payload.newRecord is expected, but we keep it defensive:
      // it can be Map, or can be missing/empty depending on realtime payload.
      final dynamic recDyn = (payload as dynamic).newRecord;
      if (recDyn is! Map) {
        _dbg(
          '[PlanFriendsModal][RT] ignore non-map newRecord event=$changeEvent type=${recDyn.runtimeType}',
        );
        return;
      }

      // ✅ FIX: убрали лишний cast `as Map` — после is-check он и так Map.
      final record = Map<String, dynamic>.from(recDyn);

      if (record.isEmpty) {
        _dbg(
            '[PlanFriendsModal][RT] ignore empty newRecord event=$changeEvent');
        return;
      }
      _onDeliveryChanged(record, changeEvent: changeEvent);
    }

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notification_deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => onChange(payload, 'insert'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notification_deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) => onChange(payload, 'update'),
        )
        .subscribe();

    _dbg(
      '[PlanFriendsModal][RT] subscribe channel=$channelName userId=$userId planId=$planId',
    );
  }

  void _onDeliveryChanged(
    Map<String, dynamic> record, {
    required String changeEvent,
  }) {
    if (!mounted) return;

    final userId = widget.appUserId.trim();
    final planId = widget.planId.trim();
    if (userId.isEmpty || planId.isEmpty) return;

    final payload = _decodePayload(record['payload']);

    // Where type can live in practice:
    // - payload['type'] (preferred, canonical)
    // - record['type'] (if delivery has a top-level type column)
    // - record['event_type'] (if delivery stores event type outside of payload)
    final rawType = _asString(payload?['type']) ??
        _asString(record['type']) ??
        _asString(record['event_type']) ??
        _asString(record['eventType']);

    // Plan id can live in:
    // - record['plan_id'] (top-level column)
    // - payload['plan_id'] / payload['planId']
    // - nested payload['plan'] map with id
    final deliveryPlanId = _extractPlanId(record: record, payload: payload);

    final type = rawType?.trim() ?? '';
    final isPlanInvite = type.startsWith('PLAN_INTERNAL_INVITE');
    final planMatches = deliveryPlanId != null && _eqId(deliveryPlanId, planId);

    _dbg(
      '[PlanFriendsModal][RT] event=$changeEvent '
      'deliveryId=${_asString(record['delivery_id']) ?? _asString(record['id']) ?? 'n/a'} '
      'status=${_asString(record['status']) ?? 'n/a'} '
      'type=$type '
      'planId=${deliveryPlanId ?? 'null'} '
      'match(type=$isPlanInvite plan=$planMatches)',
    );

    if (!isPlanInvite) return;
    if (!planMatches) return;

    // This event is server-first and relevant to the currently opened plan.
    // Refresh server snapshot. Debounced + guarded (no polling).
    _scheduleInviteStatesRefresh(
      notifyParent: false,
      fromRealtime: true,
      reason: 'realtime:$changeEvent:$type',
    );
  }

  void _scheduleInviteStatesRefresh({
    required bool notifyParent,
    required bool fromRealtime,
    required String reason,
  }) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_kRefreshDebounce, () {
      unawaited(
        _refreshInviteStates(
          notifyParent: notifyParent,
          fromRealtime: fromRealtime,
          reason: reason,
        ),
      );
    });
  }

  Future<void> _loadAll() async {
    if (!mounted) return;

    final userId = widget.appUserId.trim();
    final planId = widget.planId.trim();

    if (userId.isEmpty || planId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      final friends = await _friendsRepository.listMyFriends(appUserId: userId);
      if (!mounted) return;
      setState(() => _friends = friends);

      final states =
          await _fetchInviteStates(ownerUserId: userId, planId: planId);
      if (!mounted) return;
      setState(() => _inviteStatesByFriendUserId = states);
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
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

  Future<void> _refreshInviteStates({
    required bool notifyParent,
    required bool fromRealtime,
    required String reason,
  }) async {
    if (!mounted) return;

    if (_refreshInFlight) {
      // Avoid dropping events: remember that we need one more refresh after current finishes.
      _refreshQueued = true;
      _queuedNotifyParent = _queuedNotifyParent || notifyParent;
      _queuedFromRealtime = _queuedFromRealtime || fromRealtime;
      _queuedReason = reason;
      _dbg(
          '[PlanFriendsModal][RT] refresh queued (inFlight=true) reason=$reason');
      return;
    }

    final userId = widget.appUserId.trim();
    final planId = widget.planId.trim();
    if (userId.isEmpty || planId.isEmpty) return;

    _refreshInFlight = true;
    _dbg('[PlanFriendsModal] refreshInviteStates start reason=$reason');

    try {
      final next =
          await _fetchInviteStates(ownerUserId: userId, planId: planId);

      if (!mounted) return;

      setState(() {
        _inviteStatesByFriendUserId = next;

        // Important: If refresh was triggered by server-first realtime event (ACCEPT/DECLINE),
        // we want the currently opened sheet to reflect the new server snapshot immediately.
        // PlanFriendsPickerSheet has optimistic local state, and on decline it can keep overlay
        // until the sheet is disposed. To keep the sheet “dumb” while still aligning UX,
        // we remount it by bumping key epoch on realtime-triggered refresh.
        if (fromRealtime) _sheetEpoch++;
      });

      if (notifyParent) {
        widget.onInviteSent?.call();
      }
    } catch (e) {
      _dbg('[PlanFriendsModal] refreshInviteStates error=$e reason=$reason');
      // No rethrow: refresh is typically fire-and-forget (unawaited).
    } finally {
      _refreshInFlight = false;

      if (_refreshQueued && mounted) {
        final qNotify = _queuedNotifyParent;
        final qFromRealtime = _queuedFromRealtime;
        final qReason = _queuedReason ?? 'queued';

        _refreshQueued = false;
        _queuedNotifyParent = false;
        _queuedFromRealtime = false;
        _queuedReason = null;

        // Run another refresh, debounced to coalesce bursts.
        _scheduleInviteStatesRefresh(
          notifyParent: qNotify,
          fromRealtime: qFromRealtime,
          reason: 'queued_after:$qReason',
        );
      }
    }
  }

  Map<String, dynamic>? _decodePayload(dynamic rawPayload) {
    if (rawPayload is Map<String, dynamic>) return rawPayload;
    if (rawPayload is Map) return rawPayload.cast<String, dynamic>();
    if (rawPayload is String) {
      try {
        final decoded = jsonDecode(rawPayload);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (e) {
        _dbg(
            '[PlanFriendsModal][RT] payload jsonDecode error=$e raw="$rawPayload"');
      }
    }
    return null;
  }

  String? _extractPlanId({
    required Map<String, dynamic> record,
    required Map<String, dynamic>? payload,
  }) {
    final direct = _asString(record['plan_id']) ?? _asString(record['planId']);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final p = payload;
    if (p == null) return null;

    final fromPayload = _asString(p['plan_id']) ??
        _asString(p['planId']) ??
        _asString(p['planID']);
    if (fromPayload != null && fromPayload.trim().isNotEmpty) {
      return fromPayload.trim();
    }

    final nestedPlan = p['plan'];
    if (nestedPlan is Map) {
      final nid = _asString(nestedPlan['id']) ??
          _asString(nestedPlan['plan_id']) ??
          _asString(nestedPlan['planId']);
      if (nid != null && nid.trim().isNotEmpty) return nid.trim();
    }

    return null;
  }

  String? _asString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    return v.toString();
  }

  bool _eqId(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == 't' || s == '1' || s == 'yes' || s == 'y';
    }
    return false;
  }

  void _dbg(String msg) {
    if (!_kDebugRealtimeLogs) return;
    if (!kDebugMode) return;
    debugPrint(msg);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return PlanFriendsPickerSheet(
        key: ValueKey('plan_friends_picker_loading_${widget.planId}'),
        friends: const [],
        onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
      );
    }

    return PlanFriendsPickerSheet(
      key: ValueKey('plan_friends_picker_${widget.planId}_$_sheetEpoch'),
      friends: _friends,
      inviteStatesByFriendUserId: _inviteStatesByFriendUserId,
      onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
      // ✅ важно: PlanFriendsPickerSheet ожидает Future<void> Function()
      onAfterInvite: () async {
        _scheduleInviteStatesRefresh(
          notifyParent: true,
          fromRealtime: false,
          reason: 'after_invite',
        );
      },
    );
  }
}
