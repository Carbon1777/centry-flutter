import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/common/plan_deleted_info_modal.dart';

enum PlanDeletedUiSource {
  foreground,
  backgroundIntent,
}

class PlanDeletedUiRequest {
  final String planId;
  final String ownerUserId;

  final String? ownerNickname;
  final String? planTitle;

  final String? title;
  final String? body;

  /// ✅ Canon: consume INBOX строго после реального UI close.
  final Future<void> Function()? onClosed;

  final PlanDeletedUiSource source;

  const PlanDeletedUiRequest({
    required this.planId,
    required this.ownerUserId,
    required this.source,
    this.ownerNickname,
    this.planTitle,
    this.title,
    this.body,
    this.onClosed,
  });

  String stableKey() {
    // Stable identity of the event (no title/body noise).
    return '$planId|$ownerUserId';
  }
}

class PlanDeletedUiCoordinator {
  PlanDeletedUiCoordinator._();

  static final PlanDeletedUiCoordinator instance = PlanDeletedUiCoordinator._();

  final Queue<PlanDeletedUiRequest> _queue = Queue();

  // ✅ Dedup with TTL to avoid double-modal due to race (INBOX + intent),
  // but never block future real events with same identity forever.
  final Map<String, DateTime> _recent = <String, DateTime>{};
  static const Duration _dedupTtl = Duration(seconds: 5);

  GlobalKey<NavigatorState>? _navigatorKey;
  bool _rootUiReady = false;
  bool _showing = false;

  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  void setRootUiReady(bool ready) {
    _rootUiReady = ready;
    if (ready) _tryShowNext();
  }

  void enqueue(PlanDeletedUiRequest request) {
    final now = DateTime.now();
    _recent.removeWhere((_, ts) => now.difference(ts) > _dedupTtl);

    final key = request.stableKey();
    final last = _recent[key];
    if (last != null && now.difference(last) <= _dedupTtl) {
      if (kDebugMode) {
        debugPrint(
          '[PlanDeletedCoordinator] enqueue ignored (dedup ttl) key=$key ageMs=${now.difference(last).inMilliseconds}',
        );
      }
      return;
    }
    _recent[key] = now;

    _queue.add(request);
    if (kDebugMode) {
      debugPrint(
        '[PlanDeletedCoordinator] enqueue planId=${request.planId} ownerUserId=${request.ownerUserId} source=${request.source} queueSize=${_queue.length}',
      );
    }
    _tryShowNext();
  }

  void _tryShowNext() {
    if (!_rootUiReady) return;
    if (_showing) return;
    if (_queue.isEmpty) return;

    final navState = _navigatorKey?.currentState;
    final ctx = _navigatorKey?.currentContext ?? navState?.overlay?.context;
    if (ctx == null) {
      if (kDebugMode) {
        debugPrint(
          '[PlanDeletedCoordinator] cannot show: ctx=null (rootUiReady=$_rootUiReady showing=$_showing queue=${_queue.length})',
        );
      }
      return;
    }

    final next = _queue.removeFirst();
    _showing = true;

    if (kDebugMode) {
      debugPrint(
        '[PlanDeletedCoordinator] show modal planId=${next.planId} ownerUserId=${next.ownerUserId} source=${next.source}',
      );
    }

    void doShow() {
      final nav2 = _navigatorKey?.currentState;
      final ctx2 = _navigatorKey?.currentContext ?? nav2?.overlay?.context;
      if (ctx2 == null) {
        _showing = false;
        _tryShowNext();
        return;
      }

      showDialog<void>(
        context: ctx2,
        barrierDismissible: false,
        // ✅ critical: show on ROOT navigator (works from any tab/stack)
        useRootNavigator: true,
        builder: (_) {
          final title = (next.title ?? 'План был удален').trim();
          final body = _resolveBody(next).trim();
          return PlanDeletedInfoModal(title: title, body: body);
        },
      ).then((_) async {
        // ✅ Canon: consume only AFTER close (caller provides closure).
        try {
          final cb = next.onClosed;
          if (cb != null) await cb();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[PlanDeletedCoordinator] onClosed failed: $e');
          }
        } finally {
          _showing = false;
          _tryShowNext();
        }
      });
    }

    // ✅ Show ASAP when idle; otherwise defer to next frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      Future.microtask(doShow);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doShow());
    }
  }

  String _resolveBody(PlanDeletedUiRequest r) {
    final body = (r.body ?? '').trim();
    if (body.isNotEmpty) return body;

    final ownerNick = (r.ownerNickname ?? '').trim();
    final plan = (r.planTitle ?? '').trim();

    if (ownerNick.isNotEmpty && plan.isNotEmpty) {
      return 'Пользователь «$ownerNick» удалил план «$plan».';
    }
    if (plan.isNotEmpty) {
      return 'План «$plan» был удален.';
    }
    return 'План был удален.';
  }
}
