import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

@immutable
class InviteUiToastRequest {
  final String message;
  final String? planId;
  final InviteUiSource source;

  const InviteUiToastRequest({
    required this.message,
    this.planId,
    this.source = InviteUiSource.unknown,
  });

  @override
  String toString() =>
      'InviteUiToastRequest(message=$message, planId=$planId, source=$source)';
}

@immutable
class OwnerResultUiRequest {
  final String inviteId;
  final String planId;
  final String action; // ACCEPT | DECLINE
  final String? title;
  final String? body;
  final InviteUiSource source;

  const OwnerResultUiRequest({
    required this.inviteId,
    required this.planId,
    required this.action,
    this.title,
    this.body,
    this.source = InviteUiSource.unknown,
  });

  String get dedupKey => '$inviteId:$action';

  @override
  String toString() =>
      'OwnerResultUiRequest(inviteId=$inviteId, planId=$planId, action=$action, source=$source)';
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

class InviteUiCoordinator {
  InviteUiCoordinator._();

  static final InviteUiCoordinator instance = InviteUiCoordinator._();

  final Queue<InviteUiRequest> _queue = Queue<InviteUiRequest>();
  final Queue<OwnerResultUiRequest> _ownerResultQueue =
      Queue<OwnerResultUiRequest>();
  final Queue<InviteUiToastRequest> _toastQueue = Queue<InviteUiToastRequest>();

  final Set<String> _queuedInviteIds = <String>{};
  final Set<String> _handledInviteIds = <String>{};

  final Set<String> _queuedOwnerResultKeys = <String>{};
  final Set<String> _handledOwnerResultKeys = <String>{};

  /// ✅ NEW: защита от дублей, пока owner-result диалог открыт/в процессе.
  final Set<String> _inFlightOwnerResultKeys = <String>{};

  GlobalKey<NavigatorState>? _navigatorKey;

  InviteUiActionHandler? _onAction;
  InviteUiOpenPlanHandler? _onOpenPlan;
  InviteUiToastHandler? _onToast;
  InviteUiErrorHandler? _onError;

  bool _rootUiReady = false;
  bool _dialogVisible = false;
  bool _isFlushing = false;

  Timer? _retryTimer;

  void attachNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _scheduleFlush();
  }

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
    _scheduleFlush();
  }

  void setRootUiReady(bool value) {
    if (_rootUiReady == value) return;
    _rootUiReady = value;
    if (_rootUiReady) {
      _scheduleFlush();
    }
  }

  bool get isRootUiReady => _rootUiReady;

  void enqueue(InviteUiRequest request) {
    if (request.inviteId.isEmpty || request.planId.isEmpty) {
      return;
    }

    if (_handledInviteIds.contains(request.inviteId)) {
      return;
    }

    if (_queuedInviteIds.contains(request.inviteId)) {
      return;
    }

    _queue.addLast(request);
    _queuedInviteIds.add(request.inviteId);

    _scheduleFlush();
  }

  void enqueueOwnerResult(OwnerResultUiRequest request) {
    if (request.inviteId.isEmpty || request.planId.isEmpty) {
      return;
    }

    final key = request.dedupKey;

    if (_handledOwnerResultKeys.contains(key)) {
      return;
    }

    if (_queuedOwnerResultKeys.contains(key)) {
      return;
    }

    // ✅ NEW: пока диалог уже показывается/обрабатывается — игнорим дубль (backgroundIntent часто дергает дважды).
    if (_inFlightOwnerResultKeys.contains(key)) {
      return;
    }

    _ownerResultQueue.add(request);
    _queuedOwnerResultKeys.add(key);

    _scheduleFlush();
  }

  void enqueueToast({
    required String message,
    String? planId,
    InviteUiSource source = InviteUiSource.unknown,
  }) {
    final m = message.trim();
    if (m.isEmpty) return;

    _toastQueue.addLast(
      InviteUiToastRequest(message: m, planId: planId, source: source),
    );

    _scheduleFlush();
  }

  void resetForDebug() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _queue.clear();
    _ownerResultQueue.clear();
    _toastQueue.clear();

    _queuedInviteIds.clear();
    _handledInviteIds.clear();
    _queuedOwnerResultKeys.clear();
    _handledOwnerResultKeys.clear();
    _inFlightOwnerResultKeys.clear();

    _dialogVisible = false;
    _isFlushing = false;
  }

  void _scheduleFlush() {
    if (_isFlushing) return;
    scheduleMicrotask(_flushIfPossible);
  }

  Future<void> _flushIfPossible() async {
    if (_isFlushing) return;
    _isFlushing = true;

    try {
      while (true) {
        if (_dialogVisible) {
          return;
        }

        if (!_rootUiReady) {
          _scheduleRetry();
          return;
        }

        if (_navigatorKey?.currentState == null ||
            _navigatorKey?.currentContext == null) {
          _scheduleRetry();
          return;
        }

        if (_onAction == null || _onOpenPlan == null || _onToast == null) {
          return;
        }

        if (_queue.isNotEmpty) {
          final request = _queue.removeFirst();
          _queuedInviteIds.remove(request.inviteId);

          await _showDialogFor(request);
          continue;
        }

        if (_ownerResultQueue.isNotEmpty) {
          final request = _ownerResultQueue.removeFirst();
          final key = request.dedupKey;

          // ✅ оставляем логику как была: снимаем queued при извлечении
          _queuedOwnerResultKeys.remove(key);

          // ✅ NEW: помечаем in-flight на время показа
          _inFlightOwnerResultKeys.add(key);

          await _showOwnerResultDialogFor(request);
          continue;
        }

        return;
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

    InviteUiDecision? decision;
    try {
      decision = await showDialog<InviteUiDecision>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(
              request.title?.trim().isNotEmpty == true
                  ? request.title!.trim()
                  : 'Приглашение в план',
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
              child: Text(
                request.body?.trim().isNotEmpty == true
                    ? request.body!.trim()
                    : 'Вас пригласили в план',
                style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.3,
                    ),
              ),
            ),
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
      await _safeOnError(e, st);
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

    try {
      final result = await onAction(request, decision);

      if (result.success) {
        _handledInviteIds.add(request.inviteId);
      }

      if (result.message != null && result.message!.trim().isNotEmpty) {
        var m = result.message!.trim();
        if (decision == InviteUiDecision.decline && !m.startsWith('⛔')) {
          m = '⛔ $m';
        }
        await onToast(m);
      }

      if (result.success &&
          decision == InviteUiDecision.accept &&
          result.openPlanId != null &&
          result.openPlanId!.isNotEmpty) {
        await onOpenPlan(result.openPlanId!);
      }
    } catch (e, st) {
      await _safeOnError(e, st);
      await onToast('Ошибка. Попробуйте еще раз.');
    } finally {
      _scheduleFlush();
    }
  }

  Future<void> _ackOwnerResultDeliveryIfPossible(
      OwnerResultUiRequest request) async {
    final client = Supabase.instance.client;
    final authUserId = client.auth.currentUser?.id;
    final authUserIdNorm = authUserId?.trim();

    if (authUserIdNorm == null || authUserIdNorm.isEmpty) {
      return;
    }

    final action = request.action.trim().toUpperCase();
    if (action != 'ACCEPT' && action != 'DECLINE') {
      return;
    }

    try {
      await client.rpc(
        'ack_plan_internal_invite_result_delivery_v1',
        params: <String, dynamic>{
          'p_app_user_id': authUserIdNorm,
          'p_invite_id': request.inviteId,
          'p_action': action,
        },
      );
    } catch (e, st) {
      await _safeOnError(e, st);
    }
  }

  Future<void> _safeOnError(Object error, StackTrace stackTrace) async {
    final onError = _onError;
    if (onError == null) return;
    try {
      await onError(error, stackTrace);
    } catch (_) {}
  }

  Future<void> _showOwnerResultDialogFor(OwnerResultUiRequest request) async {
    final context = _navigatorKey!.currentContext!;
    final key = request.dedupKey;

    _dialogVisible = true;

    final normalizedAction = request.action.trim().toUpperCase();
    final isAccept = normalizedAction == 'ACCEPT';
    final title = (request.title?.trim().isNotEmpty == true)
        ? request.title!.trim()
        : (isAccept ? 'Приглашение принято' : 'Приглашение отклонено');
    final body =
        (request.body?.trim().isNotEmpty == true) ? request.body!.trim() : '';

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          final titleStyle =
              Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                    color: isAccept ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w700,
                  );

          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
            actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: Text(title, style: titleStyle),
            content: body.isNotEmpty
                ? ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: 280, maxWidth: 360),
                    child: Text(
                      body,
                      style:
                          Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                                fontSize: 16,
                                height: 1.3,
                              ),
                    ),
                  )
                : null,
            actionsAlignment: MainAxisAlignment.center,
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Закрыть'),
              ),
            ],
          );
        },
      );

      await _ackOwnerResultDeliveryIfPossible(request);

      _handledOwnerResultKeys.add(key);
    } catch (e, st) {
      _handledOwnerResultKeys.add(key);
      _onError?.call(e, st);
    } finally {
      _inFlightOwnerResultKeys.remove(key);
      _dialogVisible = false;
      _scheduleFlush();
    }
  }

}
