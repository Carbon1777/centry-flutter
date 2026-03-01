import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/common/plan_member_removed_info_modal.dart';

enum PlanMemberRemovedUiSource {
  foreground,
  backgroundIntent,
}

class PlanMemberRemovedUiRequest {
  final String planId;
  final String removedUserId;
  final String ownerUserId;

  final String? ownerNickname;
  final String? planTitle;

  final String? title;
  final String? body;

  final PlanMemberRemovedUiSource source;

  const PlanMemberRemovedUiRequest({
    required this.planId,
    required this.removedUserId,
    required this.ownerUserId,
    required this.source,
    this.ownerNickname,
    this.planTitle,
    this.title,
    this.body,
  });

  String stableKey() {
    // Stable identity of the event, without "body/title" noise.
    return '$planId|$removedUserId|$ownerUserId';
  }
}

class PlanMemberRemovedUiCoordinator {
  PlanMemberRemovedUiCoordinator._();

  static final PlanMemberRemovedUiCoordinator instance =
      PlanMemberRemovedUiCoordinator._();

  final Queue<PlanMemberRemovedUiRequest> _queue = Queue();

  // ✅ Dedup with TTL to avoid double-modal due to race (INBOX + intent),
  // but never block future real events with same text.
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

  void enqueue(PlanMemberRemovedUiRequest request) {
    final now = DateTime.now();
    _recent.removeWhere((_, ts) => now.difference(ts) > _dedupTtl);

    final key = request.stableKey();
    final last = _recent[key];
    if (last != null && now.difference(last) <= _dedupTtl) {
      if (kDebugMode) {
        debugPrint(
          '[PlanMemberRemovedCoordinator] enqueue ignored (dedup ttl) key=$key ageMs=${now.difference(last).inMilliseconds}',
        );
      }
      return;
    }
    _recent[key] = now;

    _queue.add(request);
    if (kDebugMode) {
      debugPrint(
        '[PlanMemberRemovedCoordinator] enqueue planId=${request.planId} removedUserId=${request.removedUserId} ownerUserId=${request.ownerUserId} source=${request.source} queueSize=${_queue.length}',
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
          '[PlanMemberRemovedCoordinator] cannot show: ctx=null (rootUiReady=$_rootUiReady showing=$_showing queue=${_queue.length})',
        );
      }
      return;
    }

    final next = _queue.removeFirst();
    _showing = true;

    if (kDebugMode) {
      debugPrint(
        '[PlanMemberRemovedCoordinator] show modal planId=${next.planId} removedUserId=${next.removedUserId} ownerUserId=${next.ownerUserId} source=${next.source}',
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
        // ✅ critical: show on ROOT navigator (works from Places tab, etc.)
        useRootNavigator: true,
        builder: (_) {
          final title = (next.title ?? 'Вас удалили из плана').trim();
          final body = _resolveBody(next).trim();
          return PlanMemberRemovedInfoModal(title: title, body: body);
        },
      ).then((_) {
        _showing = false;
        _tryShowNext();
      });
    }

    // ✅ If UI thread is busy building a heavy frame (Places list),
    // showing immediately can be delayed unpredictably.
    // We show ASAP when idle; otherwise defer to next frame.
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      Future.microtask(doShow);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doShow());
    }
  }

  String _resolveBody(PlanMemberRemovedUiRequest r) {
    final body = (r.body ?? '').trim();
    if (body.isNotEmpty) return body;

    final ownerNick = (r.ownerNickname ?? '').trim();
    final plan = (r.planTitle ?? '').trim();

    if (ownerNick.isNotEmpty && plan.isNotEmpty) {
      return 'Создатель «$ownerNick» удалил вас из плана «$plan».';
    }
    if (ownerNick.isNotEmpty) {
      return 'Создатель «$ownerNick» удалил вас из плана.';
    }
    if (plan.isNotEmpty) {
      return 'Создатель удалил вас из плана «$plan».';
    }
    return 'Создатель удалил вас из плана.';
  }
}
