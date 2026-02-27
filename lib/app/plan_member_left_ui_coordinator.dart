import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    return '$planId|$leftUserId|${(title ?? '').trim()}|${(body ?? '').trim()}|${(leftNickname ?? '').trim()}|${(planTitle ?? '').trim()}';
  }
}

/// Separate layer (parallel to InviteUiCoordinator):
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
    _tryShowNext();
  }

  void _tryShowNext() {
    if (!_rootUiReady) return;
    if (_showing) return;
    if (_queue.isEmpty) return;

    final nav = _navigatorKey?.currentState;
    final ctx = nav?.overlay?.context;
    if (ctx == null) return;

    final next = _queue.removeFirst();
    _showing = true;

    if (kDebugMode) {
      debugPrint(
        '[PlanMemberLeftCoordinator] show modal planId=${next.planId} leftUserId=${next.leftUserId} source=${next.source}',
      );
    }

    // No await: keep the queue flowing via then().
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) {
        final title = (next.title ?? 'Участник покинул план').trim();
        final body = _resolveBody(next).trim();
        return PlanMemberLeftInfoModal(title: title, body: body);
      },
    ).then((_) {
      _showing = false;
      _tryShowNext();
    });
  }

  String _resolveBody(PlanMemberLeftUiRequest r) {
    // If server already provided body, keep it (server-first).
    final body = (r.body ?? '').trim();
    if (body.isNotEmpty) return body;

    final nick = (r.leftNickname ?? '').trim();
    final plan = (r.planTitle ?? '').trim();

    // Canon UX: mirror owner invite-result style with «…».
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
