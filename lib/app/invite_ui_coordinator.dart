import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum InviteUiSource {
  foreground,
  backgroundIntent,
  terminatedLaunch,
  unknown,
}

enum InviteUiDecision {
  accept,
  decline,
}

@immutable
class InviteUiRequest {
  final String inviteId;
  final String planId;
  final String? title;
  final String? body;

  /// Не бизнес-логика. Просто полезный transport-параметр,
  /// если серверный контракт требует action_token при accept/decline.
  final String? actionToken;

  final InviteUiSource source;

  const InviteUiRequest({
    required this.inviteId,
    required this.planId,
    this.title,
    this.body,
    this.actionToken,
    this.source = InviteUiSource.unknown,
  });

  InviteUiRequest copyWith({
    String? inviteId,
    String? planId,
    String? title,
    String? body,
    String? actionToken,
    InviteUiSource? source,
  }) {
    return InviteUiRequest(
      inviteId: inviteId ?? this.inviteId,
      planId: planId ?? this.planId,
      title: title ?? this.title,
      body: body ?? this.body,
      actionToken: actionToken ?? this.actionToken,
      source: source ?? this.source,
    );
  }

  @override
  String toString() {
    return 'InviteUiRequest(inviteId=$inviteId, planId=$planId, source=$source)';
  }
}

@immutable
class InviteUiActionResult {
  final bool success;

  /// Что показать пользователю (toast/snackbar).
  final String? message;

  /// Если accept успешен и нужно открыть детали плана — передаем planId сюда.
  final String? openPlanId;

  const InviteUiActionResult({
    required this.success,
    this.message,
    this.openPlanId,
  });

  const InviteUiActionResult.success({
    String? message,
    String? openPlanId,
  }) : this(
          success: true,
          message: message,
          openPlanId: openPlanId,
        );

  const InviteUiActionResult.failure({
    String? message,
  }) : this(
          success: false,
          message: message,
          openPlanId: null,
        );
}

typedef InviteUiActionHandler = Future<InviteUiActionResult> Function(
  InviteUiRequest request,
  InviteUiDecision decision,
);

typedef InviteUiOpenPlanHandler = FutureOr<void> Function(String planId);

typedef InviteUiToastHandler = FutureOr<void> Function(String message);

typedef InviteUiErrorHandler = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
);

/// UI-only coordinator для показа invite-модалки.
/// Никакой бизнес-логики тут нет:
/// - accept/decline делает внешний callback (обычно RPC)
/// - навигацию в детали делает внешний callback
/// - toast/snackbar делает внешний callback
///
/// Важно:
/// - Работает через root navigator (navigatorKey), а не через конкретный State.
/// - Безопасен для 3 сценариев: foreground / background / terminated.
/// - Можно enqueue() вызывать до готовности UI: событие останется в очереди.
class InviteUiCoordinator {
  InviteUiCoordinator._();

  static final InviteUiCoordinator instance = InviteUiCoordinator._();

  final Queue<InviteUiRequest> _queue = Queue<InviteUiRequest>();
  final Set<String> _queuedInviteIds = <String>{};
  final Set<String> _handledInviteIds = <String>{};

  GlobalKey<NavigatorState>? _navigatorKey;

  InviteUiActionHandler? _onAction;
  InviteUiOpenPlanHandler? _onOpenPlan;
  InviteUiToastHandler? _onToast;
  InviteUiErrorHandler? _onError;

  bool _rootUiReady = false;
  bool _dialogVisible = false;
  bool _isFlushing = false;

  Timer? _retryTimer;

  /// Привязать root navigator key (например, из MaterialApp.navigatorKey).
  void attachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _log('attachNavigatorKey');
    _scheduleFlush();
  }

  /// Подключить callback-обработчики (RPC, навигация, toast).
  void configure({
    required InviteUiActionHandler onAction,
    required InviteUiOpenPlanHandler onOpenPlan,
    required InviteUiToastHandler onToast,
    InviteUiErrorHandler? onError,
  }) {
    _onAction = onAction;
    _onOpenPlan = onOpenPlan;
    _onToast = onToast;
    _onError = onError;
    _log('configure callbacks');
    _scheduleFlush();
  }

  /// Вызывать, когда app shell/root UI уже готов для показа диалогов.
  /// Например: после того как главный экран смонтирован.
  void setRootUiReady(bool value) {
    if (_rootUiReady == value) return;
    _rootUiReady = value;
    _log('setRootUiReady=$_rootUiReady');
    if (_rootUiReady) {
      _scheduleFlush();
    }
  }

  bool get isRootUiReady => _rootUiReady;

  /// Добавить invite в очередь (без дублей по inviteId).
  void enqueue(InviteUiRequest request) {
    if (request.inviteId.isEmpty || request.planId.isEmpty) {
      _log('enqueue ignored: empty inviteId/planId');
      return;
    }

    if (_handledInviteIds.contains(request.inviteId)) {
      _log('enqueue ignored: already handled inviteId=${request.inviteId}');
      return;
    }

    if (_queuedInviteIds.contains(request.inviteId)) {
      _log('enqueue ignored: already queued inviteId=${request.inviteId}');
      return;
    }

    _queue.addLast(request);
    _queuedInviteIds.add(request.inviteId);

    _log(
      'enqueue inviteId=${request.inviteId} '
      'planId=${request.planId} source=${request.source} '
      'queueSize=${_queue.length}',
    );

    _scheduleFlush();
  }

  /// Опционально: очистка состояния (полезно в debug / logout flows).
  void resetForDebug() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _queue.clear();
    _queuedInviteIds.clear();
    _handledInviteIds.clear();
    _dialogVisible = false;
    _isFlushing = false;
    _log('resetForDebug');
  }

  void _scheduleFlush() {
    if (_isFlushing) return;
    // Следующий кадр/тик — чтобы не спорить с текущим build/frame.
    scheduleMicrotask(_flushIfPossible);
  }

  Future<void> _flushIfPossible() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      while (true) {
        if (_dialogVisible) {
          _log('flush blocked: dialog already visible');
          return;
        }

        if (!_rootUiReady) {
          _log('flush blocked: root UI not ready');
          _scheduleRetry();
          return;
        }

        if (_navigatorKey?.currentState == null ||
            _navigatorKey?.currentContext == null) {
          _log('flush blocked: navigator not ready');
          _scheduleRetry();
          return;
        }

        if (_onAction == null || _onOpenPlan == null || _onToast == null) {
          _log('flush blocked: callbacks not configured');
          return;
        }

        if (_queue.isEmpty) {
          return;
        }

        final request = _queue.removeFirst();
        _queuedInviteIds.remove(request.inviteId);

        await _showDialogFor(request);
        // loop — если в очереди есть еще invite, покажем следующий
      }
    } finally {
      _isFlushing = false;
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(milliseconds: 180), () {
      _retryTimer = null;
      _scheduleFlush();
    });
  }

  Future<void> _showDialogFor(InviteUiRequest request) async {
    final navigator = _navigatorKey!.currentState!;
    final context = _navigatorKey!.currentContext!;

    _dialogVisible = true;
    _log(
      'show dialog inviteId=${request.inviteId} '
      'planId=${request.planId} source=${request.source}',
    );

    InviteUiDecision? decision;
    try {
      decision = await showDialog<InviteUiDecision>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(request.title?.trim().isNotEmpty == true
                ? request.title!.trim()
                : 'Приглашение в план'),
            content: Text(request.body?.trim().isNotEmpty == true
                ? request.body!.trim()
                : 'Вас пригласили в план'),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext, rootNavigator: true)
                        .pop(InviteUiDecision.decline),
                child: const Text('Отклонить'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext, rootNavigator: true)
                        .pop(InviteUiDecision.accept),
                child: const Text('Принять'),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      _dialogVisible = false;
      _log('show dialog error inviteId=${request.inviteId}: $e');
      await _safeOnError(e, st);
      // Вернем invite в начало очереди, чтобы не потерять.
      if (!_handledInviteIds.contains(request.inviteId) &&
          !_queuedInviteIds.contains(request.inviteId)) {
        _queue.addFirst(request);
        _queuedInviteIds.add(request.inviteId);
      }
      _scheduleRetry();
      return;
    }

    _dialogVisible = false;

    if (decision == null) {
      _log('dialog dismissed without decision inviteId=${request.inviteId}');
      // На всякий случай считаем это "без действия" и НЕ помечаем как handled.
      // Можно вернуть в очередь, но по контракту у нас barrierDismissible=false.
      return;
    }

    await _handleDecision(request, decision, navigator);
  }

  Future<void> _handleDecision(
    InviteUiRequest request,
    InviteUiDecision decision,
    NavigatorState navigator,
  ) async {
    final onAction = _onAction!;
    final onOpenPlan = _onOpenPlan!;
    final onToast = _onToast!;

    final actionName =
        decision == InviteUiDecision.accept ? 'ACCEPT' : 'DECLINE';
    _log(
      'action start inviteId=${request.inviteId} '
      'planId=${request.planId} action=$actionName',
    );

    try {
      final result = await onAction(request, decision);

      if (result.success) {
        _handledInviteIds.add(request.inviteId);
      }

      if (result.message != null && result.message!.trim().isNotEmpty) {
        await onToast(result.message!.trim());
      }

      if (result.success &&
          decision == InviteUiDecision.accept &&
          result.openPlanId != null &&
          result.openPlanId!.isNotEmpty) {
        _log(
          'open plan request inviteId=${request.inviteId} '
          'planId=${result.openPlanId}',
        );
        await onOpenPlan(result.openPlanId!);
      }

      _log(
        'action done inviteId=${request.inviteId} '
        'action=$actionName success=${result.success}',
      );
    } catch (e, st) {
      _log(
        'action error inviteId=${request.inviteId} '
        'action=$actionName error=$e',
      );

      await _safeOnError(e, st);

      // Покажем fallback-ошибку, если внешний слой не показал свой toast.
      await onToast('Ошибка. Попробуйте еще раз.');

      // Важно: не помечаем handled. Можно переотправить/повторить.
    } finally {
      // После завершения действия пробуем показать следующий invite.
      _scheduleFlush();
    }
  }

  Future<void> _safeOnError(Object error, StackTrace stackTrace) async {
    final onError = _onError;
    if (onError == null) return;
    try {
      await onError(error, stackTrace);
    } catch (_) {
      // Не валим coordinator из-за ошибки в логгере.
    }
  }

  void _log(String message) {
    debugPrint('[InviteCoordinator] $message');
  }
}
