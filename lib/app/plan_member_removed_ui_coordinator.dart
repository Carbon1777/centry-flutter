import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  String dedupKey() {
    return '$planId|$removedUserId|$ownerUserId|'
        '${(title ?? '').trim()}|${(body ?? '').trim()}|'
        '${(ownerNickname ?? '').trim()}|${(planTitle ?? '').trim()}';
  }
}

class PlanMemberRemovedUiCoordinator {
  PlanMemberRemovedUiCoordinator._();

  static final PlanMemberRemovedUiCoordinator instance =
      PlanMemberRemovedUiCoordinator._();

  final Queue<PlanMemberRemovedUiRequest> _queue = Queue();
  final LinkedHashSet<String> _dedup = LinkedHashSet();

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
    final key = request.dedupKey();
    if (_dedup.contains(key)) return;

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

    // More robust context resolution:
    // - currentContext exists when NavigatorState is mounted
    // - overlay.context exists when overlay is available
    final BuildContext? ctx =
        _navigatorKey?.currentContext ?? nav?.overlay?.context;

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

    // Show on next frame to avoid "during build" issues and to decouple from current screen transitions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // It's possible that root UI got unmounted between enqueue and frame callback.
      final nav2 = _navigatorKey?.currentState;
      final BuildContext? ctx2 =
          _navigatorKey?.currentContext ?? nav2?.overlay?.context;

      if (ctx2 == null) {
        _showing = false;
        _tryShowNext();
        return;
      }

      showDialog<void>(
        context: ctx2,
        barrierDismissible: false,
        // ✅ critical: ensure dialog is shown on the ROOT navigator,
        // not on a nested (Plans/Details) navigator.
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
    });
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
