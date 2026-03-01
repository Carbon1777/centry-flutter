import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/common/plan_member_joined_by_invite_info_modal.dart';

enum PlanMemberJoinedByInviteUiSource {
  foreground,
  backgroundIntent,
}

class PlanMemberJoinedByInviteUiRequest {
  final String planId;
  final String joinedUserId;

  /// Optional server-provided fields.
  final String? joinedNickname;
  final String? planTitle;

  /// Optional pre-rendered text from the server/push.
  final String? title;
  final String? body;

  final PlanMemberJoinedByInviteUiSource source;

  const PlanMemberJoinedByInviteUiRequest({
    required this.planId,
    required this.joinedUserId,
    required this.source,
    this.joinedNickname,
    this.planTitle,
    this.title,
    this.body,
  });

  /// Stable identity for dedup (do NOT dedup by text only).
  String stableKey() => '$planId|$joinedUserId';
}

class PlanMemberJoinedByInviteUiCoordinator {
  PlanMemberJoinedByInviteUiCoordinator._();

  static final PlanMemberJoinedByInviteUiCoordinator instance =
      PlanMemberJoinedByInviteUiCoordinator._();

  final Queue<PlanMemberJoinedByInviteUiRequest> _queue = Queue();

  // Short TTL dedup to avoid double modal due to races (INBOX + intent).
  final Map<String, DateTime> _recent = <String, DateTime>{};
  static const Duration _dedupTtl = Duration(seconds: 5);

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _rootUiReady = false;
  bool _showing = false;

  bool _retryScheduled = false;

  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void setRootUiReady(bool ready) {
    _rootUiReady = ready;
    if (ready) _tryShowNext();
  }

  void enqueue(PlanMemberJoinedByInviteUiRequest request) {
    final now = DateTime.now();

    // Cleanup old dedup entries.
    _recent.removeWhere((_, ts) => now.difference(ts) > _dedupTtl);

    final key = request.stableKey();
    final last = _recent[key];
    if (last != null && now.difference(last) <= _dedupTtl) {
      if (kDebugMode) {
        debugPrint(
          '[PlanMemberJoinedByInviteCoordinator] enqueue ignored (dedup ttl) key=$key ageMs=${now.difference(last).inMilliseconds}',
        );
      }
      return;
    }
    _recent[key] = now;

    _queue.add(request);

    if (kDebugMode) {
      debugPrint(
        '[PlanMemberJoinedByInviteCoordinator] enqueue planId=${request.planId} joinedUserId=${request.joinedUserId} source=${request.source} queue=${_queue.length}',
      );
    }

    _tryShowNext();
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    _retryScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      _tryShowNext();
    });
  }

  void _tryShowNext() {
    if (!_rootUiReady) return;
    if (_showing) return;
    if (_queue.isEmpty) return;

    final nav = _navigatorKey?.currentState;
    final ctx = _navigatorKey?.currentContext ?? nav?.overlay?.context;
    if (ctx == null) {
      if (kDebugMode) {
        debugPrint(
          '[PlanMemberJoinedByInviteCoordinator] ctx=null -> retry next frame (rootUiReady=$_rootUiReady showing=$_showing queue=${_queue.length})',
        );
      }
      _scheduleRetry();
      return;
    }

    // Do NOT dequeue yet. Dequeue only when we are sure we can show.
    final next = _queue.first;
    _showing = true;

    if (kDebugMode) {
      debugPrint(
        '[PlanMemberJoinedByInviteCoordinator] show requested planId=${next.planId} joinedUserId=${next.joinedUserId} source=${next.source}',
      );
    }

    Future<void> doShow() async {
      final nav2 = _navigatorKey?.currentState;
      final ctx2 = _navigatorKey?.currentContext ?? nav2?.overlay?.context;

      if (ctx2 == null) {
        if (kDebugMode) {
          debugPrint(
            '[PlanMemberJoinedByInviteCoordinator] ctx2=null -> retry (queue=${_queue.length})',
          );
        }
        _showing = false;
        _scheduleRetry();
        return;
      }

      // Now safe to dequeue.
      _queue.removeFirst();

      try {
        final title =
            (next.title ?? 'Участник вступил в план по Invite').trim();
        final body = _resolveBody(next).trim();

        await showDialog<void>(
          context: ctx2,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => PlanMemberJoinedByInviteInfoModal(
            title: title,
            body: body,
          ),
        );
      } catch (e) {
        // Avoid silent drops during navigator churn.
        _queue.addFirst(next);

        if (kDebugMode) {
          debugPrint(
            '[PlanMemberJoinedByInviteCoordinator] showDialog failed: $e (requeued, retry)',
          );
        }
        _scheduleRetry();
      } finally {
        _showing = false;
        _tryShowNext();
      }
    }

    // Schedule in a safe phase.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      Future.microtask(doShow);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doShow());
    }
  }

  String _resolveBody(PlanMemberJoinedByInviteUiRequest r) {
    // Server-first: if server already provided body, keep it.
    final body = (r.body ?? '').trim();
    if (body.isNotEmpty) return body;

    final nick = (r.joinedNickname ?? '').trim();
    final plan = (r.planTitle ?? '').trim();

    // Required canonical text (no quotes).
    if (nick.isNotEmpty && plan.isNotEmpty) {
      return 'Участник $nick вступил в план $plan по Invite';
    }
    if (nick.isNotEmpty) {
      return 'Участник $nick вступил в план по Invite';
    }
    if (plan.isNotEmpty) {
      return 'Участник вступил в план $plan по Invite';
    }
    return 'Участник вступил в план по Invite';
  }
}
