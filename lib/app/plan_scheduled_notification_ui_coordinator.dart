import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../ui/common/plan_scheduled_notification_info_modal.dart';

enum PlanScheduledNotificationUiSource {
  foreground,
  backgroundIntent,
}

class PlanScheduledNotificationUiRequest {
  final String type;
  final String planId;

  /// Canonical event correlation key from INBOX / push.
  /// If present, dedup must prefer this over text-based heuristics.
  final String? eventId;

  final String? planTitle;
  final String? eventAt;
  final String? eventDatetimeLabel;
  final String? placeTitle;

  /// Server-first rendered text.
  final String? title;
  final String? body;

  final PlanScheduledNotificationUiSource source;

  const PlanScheduledNotificationUiRequest({
    required this.type,
    required this.planId,
    required this.source,
    this.eventId,
    this.planTitle,
    this.eventAt,
    this.eventDatetimeLabel,
    this.placeTitle,
    this.title,
    this.body,
  });

  String dedupKey() {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      return 'event:$eid';
    }

    return '$type|$planId|'
        '${(planTitle ?? '').trim()}|'
        '${(eventAt ?? '').trim()}|'
        '${(eventDatetimeLabel ?? '').trim()}|'
        '${(placeTitle ?? '').trim()}|'
        '${(title ?? '').trim()}|'
        '${(body ?? '').trim()}';
  }
}

/// Separate isolated layer for new scheduled plan notifications:
/// - queues events
/// - deduplicates
/// - shows generic in-app info modal when root UI is ready
///
/// Intentionally does NOT mix with existing invite/friend/plan-member coordinators.
class PlanScheduledNotificationUiCoordinator {
  PlanScheduledNotificationUiCoordinator._();

  static final PlanScheduledNotificationUiCoordinator instance =
      PlanScheduledNotificationUiCoordinator._();

  final Queue<PlanScheduledNotificationUiRequest> _queue = Queue();
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

  void enqueue(PlanScheduledNotificationUiRequest request) {
    final key = request.dedupKey();
    if (_dedup.contains(key)) {
      if (kDebugMode) {
        debugPrint(
          '[PlanScheduledNotificationCoordinator] skip duplicate '
          'key=$key type=${request.type} planId=${request.planId} eventId=${request.eventId}',
        );
      }
      return;
    }

    _dedup.add(key);
    while (_dedup.length > 300) {
      _dedup.remove(_dedup.first);
    }

    _queue.add(request);

    if (kDebugMode) {
      debugPrint(
        '[PlanScheduledNotificationCoordinator] enqueue '
        'type=${request.type} planId=${request.planId} eventId=${request.eventId} '
        'source=${request.source} queue=${_queue.length}',
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
          '[PlanScheduledNotificationCoordinator] ctx=null -> retry next frame '
          '(rootUiReady=$_rootUiReady showing=$_showing queue=${_queue.length})',
        );
      }
      _scheduleRetry();
      return;
    }

    final next = _queue.first;
    _showing = true;

    if (kDebugMode) {
      debugPrint(
        '[PlanScheduledNotificationCoordinator] show requested '
        'type=${next.type} planId=${next.planId} eventId=${next.eventId} '
        'source=${next.source}',
      );
    }

    Future<void> doShow() async {
      final nav2 = _navigatorKey?.currentState;
      final ctx2 = _navigatorKey?.currentContext ?? nav2?.overlay?.context;

      if (ctx2 == null) {
        if (kDebugMode) {
          debugPrint(
            '[PlanScheduledNotificationCoordinator] ctx2=null -> retry '
            '(queue=${_queue.length})',
          );
        }
        _showing = false;
        _scheduleRetry();
        return;
      }

      _queue.removeFirst();

      try {
        await showDialog<void>(
          context: ctx2,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) {
            final resolvedTitle = _resolveTitle(next).trim();
            final resolvedBody = _resolveBody(next).trim();
            return PlanScheduledNotificationInfoModal(
              title: resolvedTitle,
              body: resolvedBody,
            );
          },
        );
      } catch (e) {
        _queue.addFirst(next);

        if (kDebugMode) {
          debugPrint(
            '[PlanScheduledNotificationCoordinator] showDialog failed: $e '
            '(requeued, retry)',
          );
        }
        _scheduleRetry();
      } finally {
        _showing = false;
        _tryShowNext();
      }
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle) {
      Future.microtask(doShow);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => doShow());
    }
  }

  String _resolveTitle(PlanScheduledNotificationUiRequest r) {
    final serverTitle = (r.title ?? '').trim();
    if (serverTitle.isNotEmpty) return serverTitle;

    switch (r.type.trim()) {
      case 'PLAN_VOTING_REMINDER_DATE':
        return 'Выберите дату';
      case 'PLAN_VOTING_REMINDER_PLACE':
        return 'Выберите место';
      case 'PLAN_VOTING_REMINDER_BOTH':
        return 'Завершите голосование';
      case 'PLAN_OWNER_PRIORITY_DATE':
        return 'Выберите приоритетную дату';
      case 'PLAN_OWNER_PRIORITY_PLACE':
        return 'Выберите приоритетное место';
      case 'PLAN_OWNER_PRIORITY_BOTH':
        return 'Выберите приоритет';
      case 'PLAN_EVENT_REMINDER_24H':
        return 'Мероприятие';
      default:
        return 'Уведомление';
    }
  }

  String _resolveBody(PlanScheduledNotificationUiRequest r) {
    final serverBody = (r.body ?? '').trim();
    if (serverBody.isNotEmpty) return serverBody;

    final plan = (r.planTitle ?? '').trim();
    final eventDateTime = (r.eventDatetimeLabel ?? '').trim();
    final place = (r.placeTitle ?? '').trim();

    switch (r.type.trim()) {
      case 'PLAN_VOTING_REMINDER_DATE':
        if (plan.isNotEmpty) {
          return 'Вы еще не проголосовали за дату в плане «$plan».';
        }
        return 'Вы еще не проголосовали за дату.';

      case 'PLAN_VOTING_REMINDER_PLACE':
        if (plan.isNotEmpty) {
          return 'Вы еще не проголосовали за место в плане «$plan».';
        }
        return 'Вы еще не проголосовали за место.';

      case 'PLAN_VOTING_REMINDER_BOTH':
        if (plan.isNotEmpty) {
          return 'Вы еще не выбрали дату и место в плане «$plan».';
        }
        return 'Вы еще не выбрали дату и место.';

      case 'PLAN_OWNER_PRIORITY_DATE':
        if (plan.isNotEmpty) {
          return 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по дате еще не определен. '
              'Выберите приоритетную дату среди лидирующих вариантов.';
        }
        return 'Победитель по дате еще не определен. '
            'Выберите приоритетную дату среди лидирующих вариантов.';

      case 'PLAN_OWNER_PRIORITY_PLACE':
        if (plan.isNotEmpty) {
          return 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по месту еще не определен. '
              'Выберите приоритетное место среди лидирующих вариантов.';
        }
        return 'Победитель по месту еще не определен. '
            'Выберите приоритетное место среди лидирующих вариантов.';

      case 'PLAN_OWNER_PRIORITY_BOTH':
        if (plan.isNotEmpty) {
          return 'До дедлайна голосования в плане «$plan» осталось меньше 12 часов, '
              'а победитель по дате и месту еще не определен. '
              'Выберите приоритетные дату и место среди лидирующих вариантов.';
        }
        return 'Победитель по дате и месту еще не определен. '
            'Выберите приоритетные дату и место среди лидирующих вариантов.';

      case 'PLAN_EVENT_REMINDER_24H':
        if (plan.isNotEmpty && eventDateTime.isNotEmpty && place.isNotEmpty) {
          return 'По плану «$plan» $eventDateTime у вас запланировано мероприятие в «$place».';
        }
        if (plan.isNotEmpty && eventDateTime.isNotEmpty) {
          return 'По плану «$plan» $eventDateTime у вас запланировано мероприятие.';
        }
        return 'У вас запланировано мероприятие.';

      default:
        return '';
    }
  }
}
