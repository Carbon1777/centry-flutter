import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import 'plan_friends_picker_sheet.dart';

class PlanFriendsModal extends StatefulWidget {
  final String appUserId;
  final String planId;
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;
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

class _PlanFriendsModalState extends State<PlanFriendsModal>
    with WidgetsBindingObserver {
  static const Duration _kRefreshDebounce = Duration(milliseconds: 250);
  static const bool _kDebugRealtimeLogs = true;

  // Realtime retry/backoff (NOT polling; only when channel closes/errors).
  static const Duration _kRtRetryBase = Duration(milliseconds: 300);
  static const Duration _kRtRetryMax = Duration(seconds: 5);

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

  // Reset optimistic UI in the sheet by remounting it when server snapshot changes.
  int _sheetEpoch = 0;

  // Realtime retry state
  Timer? _rtRetryTimer;
  int _rtRetryAttempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _client = Supabase.instance.client;
    _friendsRepository = FriendsRepositoryImpl(_client);

    _startRealtime();
    unawaited(_loadAll());
  }

  @override
  void didUpdateWidget(covariant PlanFriendsModal oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.appUserId != widget.appUserId ||
        oldWidget.planId != widget.planId) {
      _stopRealtime();
      _startRealtime();
      unawaited(_loadAll());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _dbg(
          '[PlanFriendsModal][LIFECYCLE] resumed -> restart realtime + refresh');
      _restartRealtimeAndRefresh(reason: 'app_resumed');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _rtRetryTimer?.cancel();
    _rtRetryTimer = null;

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

  void _restartRealtimeAndRefresh({required String reason}) {
    _rtRetryTimer?.cancel();
    _rtRetryTimer = null;
    _rtRetryAttempt = 0;

    _stopRealtime();
    _startRealtime();

    _scheduleInviteStatesRefresh(
      notifyParent: false,
      fromRealtime: true,
      reason: reason,
    );
  }

  Duration _computeRtBackoff(int attempt) {
    // 300ms, 600ms, 1200ms, 2400ms, 4800ms, capped at 5s.
    var ms = _kRtRetryBase.inMilliseconds * (1 << (attempt.clamp(0, 20)));
    if (ms > _kRtRetryMax.inMilliseconds) ms = _kRtRetryMax.inMilliseconds;
    return Duration(milliseconds: ms);
  }

  void _scheduleRealtimeRetry(String reason) {
    if (!mounted) return;
    if (_rtRetryTimer?.isActive == true) return;

    final delay = _computeRtBackoff(_rtRetryAttempt);
    _rtRetryAttempt = (_rtRetryAttempt + 1).clamp(0, 30);

    _dbg(
      '[PlanFriendsModal][RT] schedule retry in ${delay.inMilliseconds}ms reason=$reason',
    );

    _rtRetryTimer = Timer(delay, () {
      if (!mounted) return;
      _dbg(
        '[PlanFriendsModal][RT] retry now reason=$reason attempt=$_rtRetryAttempt',
      );
      _stopRealtime();
      _startRealtime();

      // After resubscribe we also refresh server snapshot to catch missed events.
      _scheduleInviteStatesRefresh(
        notifyParent: false,
        fromRealtime: true,
        reason: 'rt_retry:$reason',
      );
    });
  }

  void _startRealtime() {
    final userId = widget.appUserId.trim();
    final planId = widget.planId.trim();
    if (userId.isEmpty || planId.isEmpty) return;

    final channelName = 'plan_friends_modal_${planId}_$userId';
    _channel = _client.channel(channelName);

    void onChange(dynamic payload, String changeEvent) {
      final dynamic recDyn = (payload as dynamic).newRecord;
      if (recDyn is! Map) {
        _dbg(
          '[PlanFriendsModal][RT] ignore non-map newRecord event=$changeEvent type=${recDyn.runtimeType}',
        );
        return;
      }

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
        );

    // ✅ Critical: handle subscribe status and retry on closed/error.
    _channel!.subscribe((status, [err]) {
      _dbg(
          '[PlanFriendsModal][RT] status=$status err=$err channel=$channelName');

      if (status == RealtimeSubscribeStatus.subscribed) {
        // Reset retry counter and refresh once to catch missed deliveries.
        _rtRetryTimer?.cancel();
        _rtRetryTimer = null;
        _rtRetryAttempt = 0;

        _scheduleInviteStatesRefresh(
          notifyParent: false,
          fromRealtime: true,
          reason: 'rt_subscribed',
        );
        return;
      }

      if (status == RealtimeSubscribeStatus.closed ||
          status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _scheduleRealtimeRetry('status:$status');
      }
    });

    _dbg(
      '[PlanFriendsModal][RT] subscribe channel=$channelName userId=$userId planId=$planId',
    );
  }

  bool _isRelevantForInviteStates(String typeStr) {
    // ✅ было: только PLAN_INTERNAL_INVITE*
    // ✅ нужно: любые изменения состава плана тоже меняют is_member/can_invite.
    if (typeStr.startsWith('PLAN_INTERNAL_INVITE')) return true;

    // Membership change events (server-first)
    switch (typeStr) {
      case 'PLAN_MEMBER_LEFT':
      case 'PLAN_MEMBER_REMOVED':
      case 'PLAN_MEMBER_JOINED':
      case 'PLAN_MEMBER_JOINED_BY_INVITE':
      case 'PLAN_DELETED':
        return true;
    }

    return false;
  }

  void _onDeliveryChanged(
    Map<String, dynamic> record, {
    required String changeEvent,
  }) {
    if (!mounted) return;

    final planId = widget.planId.trim();
    if (planId.isEmpty) return;

    final outer = _decodePayload(record['payload']);
    final inner =
        _decodePayload(outer?['payload']); // payload может быть вложенным

    final type = _extractType(record: record, outer: outer, inner: inner);
    final typeStr = (type ?? 'unknown').trim();

    final deliveryPlanId =
        _extractPlanId(record: record, outer: outer, inner: inner);

    final planMatches = deliveryPlanId != null && _eqId(deliveryPlanId, planId);

    final isRelevant = _isRelevantForInviteStates(typeStr);

    _dbg(
      '[PlanFriendsModal][RT] event=$changeEvent '
      'id=${_asString(record['id']) ?? 'n/a'} '
      'status=${_asString(record['status']) ?? 'n/a'} '
      'type=$typeStr '
      'planId=${deliveryPlanId ?? 'null'} '
      'match(relevant=$isRelevant plan=$planMatches)',
    );

    if (!isRelevant) return;

    // Even if plan_id can't be extracted (format variations), refresh is safer than stuck UI.
    if (planMatches || deliveryPlanId == null) {
      _scheduleInviteStatesRefresh(
        notifyParent: false,
        fromRealtime: true,
        reason: 'realtime:$changeEvent:$typeStr',
      );
    }
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
      _refreshQueued = true;
      _queuedNotifyParent = _queuedNotifyParent || notifyParent;
      _queuedFromRealtime = _queuedFromRealtime || fromRealtime;
      _queuedReason = reason;
      _dbg('[PlanFriendsModal][RT] refresh queued reason=$reason');
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
        if (fromRealtime) _sheetEpoch++; // reset optimistic
      });

      if (notifyParent) {
        widget.onInviteSent?.call();
      }
    } catch (e) {
      _dbg('[PlanFriendsModal] refreshInviteStates error=$e reason=$reason');
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

        _scheduleInviteStatesRefresh(
          notifyParent: qNotify,
          fromRealtime: qFromRealtime,
          reason: 'queued_after:$qReason',
        );
      }
    }
  }

  Map<String, dynamic>? _decodePayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (e) {
        _dbg('[PlanFriendsModal][RT] jsonDecode error=$e raw="$raw"');
      }
    }
    return null;
  }

  String? _extractType({
    required Map<String, dynamic> record,
    required Map<String, dynamic>? outer,
    required Map<String, dynamic>? inner,
  }) {
    return _asString(outer?['type']) ??
        _asString(outer?['event_type']) ??
        _asString(outer?['eventType']) ??
        _asString(inner?['type']) ??
        _asString(inner?['event_type']) ??
        _asString(inner?['eventType']) ??
        _asString(record['type']) ??
        _asString(record['event_type']) ??
        _asString(record['eventType']);
  }

  String? _extractPlanId({
    required Map<String, dynamic> record,
    required Map<String, dynamic>? outer,
    required Map<String, dynamic>? inner,
  }) {
    final direct = _asString(record['plan_id']) ?? _asString(record['planId']);
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();

    final o = outer;
    if (o != null) {
      final p = _asString(o['plan_id']) ??
          _asString(o['planId']) ??
          _asString(o['planID']);
      if (p != null && p.trim().isNotEmpty) return p.trim();

      final nestedPlan = o['plan'];
      if (nestedPlan is Map) {
        final nid = _asString(nestedPlan['id']) ??
            _asString(nestedPlan['plan_id']) ??
            _asString(nestedPlan['planId']);
        if (nid != null && nid.trim().isNotEmpty) return nid.trim();
      }
    }

    final i = inner;
    if (i != null) {
      final p = _asString(i['plan_id']) ??
          _asString(i['planId']) ??
          _asString(i['planID']);
      if (p != null && p.trim().isNotEmpty) return p.trim();

      final nestedPlan = i['plan'];
      if (nestedPlan is Map) {
        final nid = _asString(nestedPlan['id']) ??
            _asString(nestedPlan['plan_id']) ??
            _asString(nestedPlan['planId']);
        if (nid != null && nid.trim().isNotEmpty) return nid.trim();
      }
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
