import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/common/plan_member_left_info_modal.dart';

enum PlanMemberLeftUiSource {
  foreground,
  backgroundIntent,
}

class PlanMemberLeftUiRequest {
  final String planId;
  final String leftUserId;

  /// Optional server-provided fields for better UX text.
  final String? leftNickname;
  final String? planTitle;

  /// Optional pre-rendered text from the server/push.
  final String? title;
  final String? body;

  final PlanMemberLeftUiSource source;

  const PlanMemberLeftUiRequest({
    required this.planId,
    required this.leftUserId,
    required this.source,
    this.leftNickname,
    this.planTitle,
    this.title,
    this.body,
  });

  String dedupKey() {
    return '$planId|$leftUserId|'
        '${(title ?? '').trim()}|${(body ?? '').trim()}|'
        '${(leftNickname ?? '').trim()}|${(planTitle ?? '').trim()}';
  }
}

/// Separate layer:
/// - queues events
/// - deduplicates
/// - shows a simple in-app info modal when root UI is ready
class PlanMemberLeftUiCoordinator {
  PlanMemberLeftUiCoordinator._();

  static final PlanMemberLeftUiCoordinator instance =
      PlanMemberLeftUiCoordinator._();

  final Queue<PlanMemberLeftUiRequest> _queue = Queue();
  final LinkedHashSet<String> _dedup = LinkedHashSet();

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _rootUiReady = false;
  bool _showing = false;

  bool _retryScheduled = false;

  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void setRootUiReady(bool ready) {
    _rootUiReady = ready;
    if (ready) {
      _tryShowNext();
    }
  }

  void enqueue(PlanMemberLeftUiRequest request) {
    final key = request.dedupKey();
    if (_dedup.contains(key)) return;

    // Keep dedup set bounded.
    _dedup.add(key);
    while (_dedup.length > 200) {
      _dedup.remove(_dedup.first);
    }

    _queue.add(request);

    if (kDebugMode) {
      debugPrint(
        '[PlanMemberLeftCoordinator] enqueue planId=${request.planId} leftUserId=${request.leftUserId} source=${request.source} queue=${_queue.length}',
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
          '[PlanMemberLeftCoordinator] ctx=null -> retry next frame (rootUiReady=$_rootUiReady showing=$_showing queue=${_queue.length})',
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
        '[PlanMemberLeftCoordinator] show requested planId=${next.planId} leftUserId=${next.leftUserId} source=${next.source}',
      );
    }

    Future<void> doShow() async {
      final nav2 = _navigatorKey?.currentState;
      final ctx2 = _navigatorKey?.currentContext ?? nav2?.overlay?.context;

      if (ctx2 == null) {
        if (kDebugMode) {
          debugPrint(
            '[PlanMemberLeftCoordinator] ctx2=null -> retry (queue=${_queue.length})',
          );
        }
        _showing = false;
        _scheduleRetry();
        return;
      }

      // Now safe to dequeue.
      _queue.removeFirst();

      try {
        await showDialog<void>(
          context: ctx2,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) {
            final title = (next.title ?? 'Участник покинул план').trim();
            final body = _resolveBody(next).trim();
            return PlanMemberLeftInfoModal(title: title, body: body);
          },
        );
      } catch (e) {
        // Avoid silent drops during navigator churn.
        _queue.addFirst(next);

        if (kDebugMode) {
          debugPrint(
            '[PlanMemberLeftCoordinator] showDialog failed: $e (requeued, retry)',
          );
        }
        _scheduleRetry();
      } finally {
        _showing = false;
        _tryShowNext();
      }
    }

    // Schedule in a safe phase (same tactic as for removed).
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      Future.microtask(doShow);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doShow());
    }
  }

  String _resolveBody(PlanMemberLeftUiRequest r) {
    // If server already provided body, keep it (server-first).
    final body = (r.body ?? '').trim();
    if (body.isNotEmpty) return body;

    final nick = (r.leftNickname ?? '').trim();
    final plan = (r.planTitle ?? '').trim();

    if (nick.isNotEmpty && plan.isNotEmpty) {
      return 'Участник «$nick» покинул план «$plan».';
    }
    if (nick.isNotEmpty) {
      return 'Участник «$nick» покинул план.';
    }
    if (plan.isNotEmpty) {
      return 'Один из участников покинул план «$plan».';
    }
    return 'Один из участников покинул план.';
  }
}
