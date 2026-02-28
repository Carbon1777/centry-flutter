import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ Firebase / FCM
import 'package:firebase_messaging/firebase_messaging.dart';

import '../data/plans/plans_repository.dart';
import '../data/plans/plans_repository_impl.dart';
import '../ui/plans/plans_screen.dart';
import '../ui/plans/plan_details_screen.dart';

import '../app_theme.dart';
import '../core/geo/geo_service.dart';
import '../data/local/user_snapshot_storage.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/nickname_screen.dart';
import '../push/push_notifications.dart';
import '../ui/common/center_toast.dart';
import 'invite_ui_coordinator.dart';
import 'plan_member_left_ui_coordinator.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: App.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),

      // ✅ ЛОКАЛИЗАЦИИ
      locale: const Locale('ru'),
      supportedLocales: const [
        Locale('ru'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      home: const BootstrapGate(),
    );
  }
}

class BootstrapGate extends StatefulWidget {
  const BootstrapGate({super.key});

  @override
  State<BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<BootstrapGate>
    with WidgetsBindingObserver {
  final _storage = UserSnapshotStorage();
  final _supabase = Supabase.instance.client;
  final _appLinks = AppLinks();
  static const MethodChannel _notificationIntentChannel =
      MethodChannel('centry/notification_intents');

  // UI strings (keep centralized to avoid drift)
  static const String kInviteDialogDefaultTitle = 'Вас пригласили в план';  static const String kInviteAcceptedToast = 'Приглашение принято';
  static const String kInviteDeclinedToast = 'Приглашение отклонено';

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<Uri>? _linkSub;

  // ✅ FCM token refresh listener
  StreamSubscription<String>? _fcmTokenSub;

  // ✅ Foreground message listener
  StreamSubscription<RemoteMessage>? _fcmMessageSub;
  // ✅ Realtime INBOX intake (foreground canonical path)
  RealtimeChannel? _inboxInvitesChannel;
  String? _inboxInvitesChannelUserId;

  // Realtime subscribe ensure() serialization + last status (infrastructure only)
  bool _inboxInvitesEnsureInProgress = false;
  bool _inboxInvitesEnsureRerunRequested = false;
  RealtimeSubscribeStatus? _inboxInvitesLastStatus;

  // Realtime retry backoff for INBOX channel health.
  Timer? _inboxInvitesRealtimeRetryTimer;
  int _inboxInvitesRealtimeRetryAttempt = 0;

  bool _restoring = true;

  String? _userId;
  String? _nickname;
  String? _publicId;
  String? _email;

  Timer? _retryTimer;

  bool _handlingPendingPlanInvite = false;

  // If server successfully applied invite, it returns plan_id.
  // We forward it to HomeScreen to immediately open PlanDetails.
  String? _pendingOpenPlanId;
  String? _pendingOpenPlanToastMessage;
  DateTime? _homeVisibleAt;
  Timer? _pendingPlanOpenTimer;
  bool _appShellReady = false;

  // Post-identity pipeline guards (avoid reentry/loops).
  bool _postIdentityFlowsRunning = false;
  bool _postIdentityFlowsRerunRequested = false;

  // ✅ Push token registration guards (UI-only, no business logic)
  bool _registeringDeviceToken = false;
  bool _registerDeviceTokenRetryRequested = false;
  String? _lastRegisteredDeviceTokenKey;

  // ✅ Prevent double-tap actions
  bool _processingInviteAction = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    InviteUiCoordinator.instance.attachNavigatorKey(App.navigatorKey);
    InviteUiCoordinator.instance.configure(
      onAction: (request, decision) async {
        await _handleInternalInviteAction(
          inviteId: request.inviteId,
          planId: request.planId,
          action: decision == InviteUiDecision.accept ? 'ACCEPT' : 'DECLINE',
          actionToken: request.actionToken,
        );
        // Existing app.dart flow already handles toast/navigation (server-first RPC -> UI reaction).
        return const InviteUiActionResult.success();
      },
      onOpenPlan: (planId) async {},
      onToast: (message) async {},
      onError: (error, stackTrace) async {
        if (kDebugMode) {
          debugPrint('[InviteCoordinator] error: $error');
        }
      },
    );
    InviteUiCoordinator.instance.setRootUiReady(false);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);

    // ✅ Separate layer: owner notifications about member leaving a plan.
    PlanMemberLeftUiCoordinator.instance.attachNavigatorKey(App.navigatorKey);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);

    unawaited(GeoService.instance.refresh());

    _initAuthListener();
    _initDeepLinks();
    _initAndroidNotificationIntentBridge();

    // ✅ local notifications init (actions)
    unawaited(_initLocalNotifications());

    // ✅ Setup FCM listeners (mobile only)
    _initFcmTokenRefresh();
    _initFcmForegroundMessages();

    _restore();
  }

  void _initAndroidNotificationIntentBridge() {
    if (kIsWeb) return;

    _notificationIntentChannel.setMethodCallHandler((call) async {
      if (call.method != 'notification_intent') return;

      try {
        final raw = call.arguments;
        final map =
            raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
        final extrasRaw = map['extras'];
        final extras = extrasRaw is Map
            ? Map<String, dynamic>.from(extrasRaw)
            : <String, dynamic>{};

        final intentData = (map['intent_data'] ?? '').toString();
        if (kDebugMode) {
          debugPrint('[IntentBridge] intent_data=$intentData extras=$extras');
        }

        // 1) Deep links (centry://..., https://www.centry.website/plan-invite?...)
        if (intentData.isNotEmpty) {
          final uri = Uri.tryParse(intentData);
          if (uri != null) {
            await _handleIncomingUri(uri);
          }
        }

        // 2) Notification tap routing (background tap on local notification)
        final actionId = (extras['actionId'] ?? extras['action_id'] ?? '')
            .toString()
            .trim()
            .toUpperCase();

        Map<String, dynamic> payload = <String, dynamic>{};
        final payloadRaw = extras['payload'];
        if (payloadRaw is Map) {
          payload = Map<String, dynamic>.from(payloadRaw);
        } else if (payloadRaw is String && payloadRaw.trim().isNotEmpty) {
          try {
            final decoded = jsonDecode(payloadRaw);
            if (decoded is Map) {
              payload = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            // ignore malformed payload
          }
        }


        // 2.a) PLAN_MEMBER_LEFT: route via the same server-generated payload as foreground (no local guessing).
        final payloadType = (payload['type'] ?? extras['type'] ?? '').toString().trim();
        if (payloadType == 'PLAN_MEMBER_LEFT') {
          final planId = (payload['plan_id'] ?? payload['planId'] ?? extras['plan_id'] ?? '').toString();
          final leftUserId = (payload['left_user_id'] ?? payload['leftUserId'] ?? extras['left_user_id'] ?? '').toString();
          if (planId.isNotEmpty && leftUserId.isNotEmpty) {
            final leftNickname = (payload['left_nickname'] ?? payload['leftNickname'] ?? '').toString().trim();
            final planTitle = (payload['plan_title'] ?? payload['planTitle'] ?? '').toString().trim();
            final title = (payload['title'] ?? '').toString().trim();
            final body = (payload['body'] ?? '').toString().trim();

            // NOTE: Keep body null when it's generic, so the coordinator can render a contextual message.
            PlanMemberLeftUiCoordinator.instance.enqueue(
              PlanMemberLeftUiRequest(
                planId: planId,
                leftUserId: leftUserId,
                leftNickname: leftNickname.isEmpty ? null : leftNickname,
                planTitle: planTitle.isEmpty ? null : planTitle,
                title: title.isEmpty ? null : title,
                body: (body.isEmpty || body == 'Один из участников покинул план.') ? null : body,
                source: PlanMemberLeftUiSource.backgroundIntent,
              ),
            );
            return;
          }
        }

        if (actionId == 'OPEN') {
          final inviteId =
              (payload['invite_id'] ?? extras['invite_id'] ?? '').toString();
          final planId =
              (payload['plan_id'] ?? extras['plan_id'] ?? '').toString();
          final title = (payload['title'] ?? '').toString();
          final body = (payload['body'] ?? '').toString();

          if (inviteId.isNotEmpty && planId.isNotEmpty) {
            // Coordinator нужен только для background-like сценария:
            // - stale callback после resume (mounted == false)
            // - или app shell уже поднят (background/foreground running app)
            // Для cold start (restoring=true, appShell=false) НЕ перехватываем здесь,
            // чтобы остался baseline-путь launchFromNotif -> local invite flow
            // с показом модалки после прохождения Home -> Feed.
            final kindStr = (payload['kind'] ?? '').toString();
            final hasOwnerAction =
                (payload['action'] ?? '').toString().isNotEmpty;
            final isOwnerResult = kindStr == 'OWNER_RESULT' || hasOwnerAction;

            // Route owner-result via coordinator even on cold start.
            final shouldRouteViaCoordinator =
                isOwnerResult || !mounted || (_appShellReady && !_restoring);

            if (kDebugMode) {
              debugPrint(
                '[IntentBridge] invite OPEN inviteId=$inviteId planId=$planId '
                'mounted=$mounted restoring=$_restoring appShell=$_appShellReady '
                'viaCoordinator=$shouldRouteViaCoordinator isOwnerResult=$isOwnerResult',
              );
            }

            if (shouldRouteViaCoordinator) {
              final kind = (payload['kind'] ?? extras['kind'] ?? '')
                  .toString()
                  .trim()
                  .toUpperCase();
              final actionValue =
                  (payload['action'] ?? '').toString().trim().toUpperCase();

              final isOwnerResult = kind == 'OWNER_RESULT' ||
                  ((actionValue == 'ACCEPT' || actionValue == 'DECLINE'));

              if (isOwnerResult) {
                final ownerTitle = actionValue == 'ACCEPT'
                    ? 'Приглашение принято'
                    : 'Приглашение отклонено';

                InviteUiCoordinator.instance.enqueueOwnerResult(
                  OwnerResultUiRequest(
                    inviteId: inviteId,
                    planId: planId,
                    action: actionValue.isEmpty ? 'DECLINE' : actionValue,
                    title: ownerTitle,
                    body: body,
                    source: InviteUiSource.backgroundIntent,
                  ),
                );
              } else {
                InviteUiCoordinator.instance.enqueue(
                  InviteUiRequest(
                    inviteId: inviteId,
                    planId: planId,
                    title: title,
                    body: body,
                    source: InviteUiSource.backgroundIntent,
                  ),
                );
              }
              return;
            }
          }
        }

        final type = (extras['type'] ?? '').toString();
        final planId = (extras['plan_id'] ?? '').toString();
        if (type == 'PLAN_INTERNAL_INVITE' && planId.isNotEmpty) {
          // Canon: tap on invite body does nothing (no ACCEPT/DECLINE, no nav).
          return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[IntentBridge] handler error: $e');
        }
      }
    });
  }

  Future<void> _initLocalNotifications() async {
    await PushNotifications.init(
      onInviteAction: ({
        required String inviteId,
        required String action,
        required String planId,
        String? actionToken,
        String? title,
        String? body,
      }) async {
        final normalized = action.trim().toUpperCase();

        // ✅ Canon: system push only opens app. Product actions happen in in-app modal.
        if (normalized == 'OPEN') {
          final t = (title ?? '').trim().toLowerCase();
          final b = (body ?? '').trim().toLowerCase();

          // Backward-compatible heuristic:
          // owner-result local notification payload previously arrived here as OPEN without explicit kind/action.
          final looksLikeOwnerResult = t.contains('приглашение принято') ||
              t.contains('приглашение отклонено') ||
              b.contains('принял приглашение') ||
              b.contains('отклонил приглашение') ||
              b.contains('приглашение принято') ||
              b.contains('приглашение отклонено');

          if (looksLikeOwnerResult) {
            final actionValue = (t.contains('принято') || b.contains('принял'))
                ? 'ACCEPT'
                : 'DECLINE';

            InviteUiCoordinator.instance.enqueueOwnerResult(
              OwnerResultUiRequest(
                inviteId: inviteId,
                planId: planId,
                action: actionValue,
                title: actionValue == 'ACCEPT'
                    ? 'Приглашение принято'
                    : 'Приглашение отклонено',
                body: body,
                source: InviteUiSource.backgroundIntent,
              ),
            );
            return;
          }

          InviteUiCoordinator.instance.enqueue(
            InviteUiRequest(
              inviteId: inviteId,
              planId: planId,
              actionToken: actionToken,
              title: title,
              body: body,
              source: InviteUiSource.backgroundIntent,
            ),
          );
          return;
        }

        // Ignore legacy/unknown actions from old notifications.
        if (kDebugMode) {
          debugPrint('[InviteModal] ignore local notif action=$normalized');
        }
      },
    
      onPlanMemberLeftOpen: ({
        required String planId,
        required String leftUserId,
        String? leftNickname,
        String? planTitle,
        String? title,
        String? body,
      }) async {
        PlanMemberLeftUiCoordinator.instance.enqueue(
          PlanMemberLeftUiRequest(
            planId: planId,
            leftUserId: leftUserId,
            leftNickname: (leftNickname ?? '').trim().isEmpty ? null : (leftNickname ?? '').trim(),
            planTitle: (planTitle ?? '').trim().isEmpty ? null : (planTitle ?? '').trim(),
            title: (title ?? '').trim().isEmpty ? null : (title ?? '').trim(),
            body: ((body ?? '').trim().isEmpty || (body ?? '').trim() == 'Один из участников покинул план.') ? null : (body ?? '').trim(),
            source: PlanMemberLeftUiSource.backgroundIntent,
          ),
        );
      },);
  }

  void _initFcmForegroundMessages() {
    if (kIsWeb) return;

    _fcmMessageSub?.cancel();

    // Foreground: show local notification (system tray) + in-app modal (canonical UX)
    if (kDebugMode) {
      debugPrint('[FCM] installing onMessage listener');
    }
    _fcmMessageSub = FirebaseMessaging.onMessage.listen((m) async {
      if (kDebugMode) {
        debugPrint('[FCM] onMessage data=${m.data}');
      }

      // Keep system notification for consistency (buttons live there too)
      await PushNotifications.showInternalInvite(m);

      // In-app modal is canonical. Queue it and show only after welcome/home phase.
      _queueInternalInviteDialogFromRemoteMessage(m);

      // ✅ Separate layer: in-app info modal when a member leaves a plan.
      _queuePlanMemberLeftDialogFromRemoteMessage(m);
    });
  }

  void _queueInternalInviteDialogFromRemoteMessage(RemoteMessage m) {
    if (!PushNotifications.isInternalInvite(m)) return;

    final inviteId = (m.data['invite_id'] ?? '').toString();
    final planId = (m.data['plan_id'] ?? '').toString();
    final actionToken = (m.data['action_token'] ?? '').toString();

    final inviterNickname = (m.data['inviter_nickname'] ??
            m.data['inviterNickname'] ??
            m.data['sender_nickname'] ??
            m.data['senderNickname'] ??
            m.data['from_nickname'] ??
            m.data['fromNickname'] ??
            '')
        .toString()
        .trim();
    final planTitle =
        (m.data['plan_title'] ?? m.data['planTitle'] ?? m.data['title'] ?? '')
            .toString()
            .trim();

    final title = kInviteDialogDefaultTitle;
    final body = (inviterNickname.isNotEmpty && planTitle.isNotEmpty)
        ? '$inviterNickname пригласил вас в план $planTitle'
        : (m.data['body'] ?? '').toString();

    if (inviteId.isEmpty || planId.isEmpty) return;

    InviteUiCoordinator.instance.enqueue(
      InviteUiRequest(
        inviteId: inviteId,
        planId: planId,
        actionToken: actionToken.isEmpty ? null : actionToken,
        title: title,
        body: body,
        source: InviteUiSource.foreground,
      ),
    );
  }

  
void _queuePlanMemberLeftDialogFromRemoteMessage(RemoteMessage m) {
  if (!PushNotifications.isPlanMemberLeft(m)) return;

  final planId = (m.data['plan_id'] ?? '').toString();
  final leftUserId =
      (m.data['left_user_id'] ?? m.data['member_user_id'] ?? '').toString();
  final leftNickname =
      (m.data['left_nickname'] ?? m.data['member_nickname'] ?? '').toString();
  final planTitle =
      (m.data['plan_title'] ?? m.data['planTitle'] ?? '').toString();

  if (planId.isEmpty || leftUserId.isEmpty) return;

  final title = (m.data['title'] ?? m.notification?.title ?? '').toString();
  final body = (m.data['body'] ?? m.notification?.body ?? '').toString();

  if (kDebugMode) {
    debugPrint(
      '[PlanMemberLeft] enqueue from foreground push planId=$planId leftUserId=$leftUserId',
    );
  }

  final cleanLeftNickname =
      leftNickname.trim().isEmpty ? null : leftNickname.trim();
  final cleanPlanTitle = planTitle.trim().isEmpty ? null : planTitle.trim();
  final cleanTitle = title.trim().isEmpty ? null : title.trim();

  final bodyTrim = body.trim();
  final cleanBody = (bodyTrim.isEmpty || bodyTrim == 'Один из участников покинул план.')
      ? null
      : bodyTrim;

  PlanMemberLeftUiCoordinator.instance.enqueue(
    PlanMemberLeftUiRequest(
      planId: planId,
      leftUserId: leftUserId,
      leftNickname: cleanLeftNickname,
      planTitle: cleanPlanTitle,
      title: cleanTitle,
      body: cleanBody,
      source: PlanMemberLeftUiSource.foreground,
    ),
  );
}


  Future<void> _ensureInboxInvitesRealtimeSubscribed() async {
    // Canonical C (foreground): consume server-fact INBOX deliveries via Realtime.
    // A/B are preserved (they already work via push-tap + intent bridge / pending dialog).
    // NOTE: do not gate realtime by `mounted` here.
    if (_restoring) return;
    if (!_appShellReady) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    // Prevent concurrent ensure() races (resume + appShellReady + retry timers).
    if (_inboxInvitesEnsureInProgress) {
      _inboxInvitesEnsureRerunRequested = true;
      return;
    }
    _inboxInvitesEnsureInProgress = true;
    _inboxInvitesEnsureRerunRequested = false;

    try {
      final existingChannel = _inboxInvitesChannel;
      final sameUserChannel =
          existingChannel != null && _inboxInvitesChannelUserId == userId;

      // Already subscribed and healthy.
      if (sameUserChannel &&
          _inboxInvitesLastStatus == RealtimeSubscribeStatus.subscribed) {
        return;
      }

      // If we have an existing channel for this user and a retry is already scheduled,
      // do not thrash by recreating the channel again.
      if (sameUserChannel && _inboxInvitesRealtimeRetryTimer != null) {
        return;
      }

      // If we have an existing channel for this user and it's currently in a non-terminal
      // state (e.g. subscribing/joining), let it settle; status callback will schedule retry if needed.
      if (sameUserChannel &&
          _inboxInvitesLastStatus != null &&
          _inboxInvitesLastStatus != RealtimeSubscribeStatus.closed &&
          _inboxInvitesLastStatus != RealtimeSubscribeStatus.channelError &&
          _inboxInvitesLastStatus != RealtimeSubscribeStatus.timedOut) {
        return;
      }

      // Decide whether we need to recreate the channel:
      // - user changed: hard reset (retry attempt resets)
      // - same user but channel is closed/error/timedOut: recreate WITHOUT resetting retry attempt
      final shouldResetRetryAttempt = !sameUserChannel;
      if (existingChannel != null) {
        await _disposeInboxInvitesRealtimeSubscription(
          resetRetry: shouldResetRetryAttempt,
        );
      }

      _inboxInvitesChannelUserId = userId;

      // Some SDK versions require explicit realtime.connect() call.
      try {
        (_supabase.realtime as dynamic).connect();
      } catch (_) {
        // ignore (connect() may not exist / may already be connected)
      }

      if (kDebugMode) {
        debugPrint(
            '[INBOX] subscribe notification_deliveries (userId=$userId)');
      }

      final channel = _supabase.channel('inbox_invites_$userId');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notification_deliveries',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          try {
            final newRow = payload.newRecord;
            if (newRow.isEmpty) return;

            // Hard-safety: never react to deliveries for other user ids.
            // NOTE: newRecord keys may come as snake_case or camelCase depending on client/runtime.
            final rowUserId = (newRow['user_id'] ??
                    newRow['userId'] ??
                    newRow['userID'] ??
                    newRow['userid'] ??
                    '')
                .toString();

            if (rowUserId.isNotEmpty && rowUserId != userId) {
              if (kDebugMode) {
                debugPrint(
                  '[INBOX] ignore delivery for other user rowUserId=$rowUserId currentUserId=$userId keys=${newRow.keys.toList()}',
                );
              }
              return;
            }

            final deliveryChannel = (newRow['channel'] ??
                    newRow['Channel'] ??
                    newRow['delivery_channel'] ??
                    newRow['deliveryChannel'] ??
                    '')
                .toString()
                .trim()
                .toUpperCase();
            final status = (newRow['status'] ??
                    newRow['Status'] ??
                    newRow['delivery_status'] ??
                    newRow['deliveryStatus'] ??
                    '')
                .toString()
                .trim()
                .toUpperCase();

            if (deliveryChannel != 'INBOX') {
              if (kDebugMode) {
                debugPrint(
                  '[INBOX] ignore non-INBOX delivery channel=$deliveryChannel status=$status keys=${newRow.keys.toList()}',
                );
              }
              return;
            }

            if (status.isNotEmpty && status != 'PENDING') {
              if (kDebugMode) {
                debugPrint(
                  '[INBOX] ignore non-PENDING delivery status=$status keys=${newRow.keys.toList()}',
                );
              }
              return;
            }

            Map<String, dynamic> payloadMap = <String, dynamic>{};
            final payloadRaw = newRow['payload'];
            if (payloadRaw is Map) {
              payloadMap = Map<String, dynamic>.from(payloadRaw);
            } else if (payloadRaw is String && payloadRaw.trim().isNotEmpty) {
              try {
                final decoded = jsonDecode(payloadRaw);
                if (decoded is Map) {
                  payloadMap = Map<String, dynamic>.from(decoded);
                }
              } catch (_) {
                // ignore malformed payload
              }
            }

            // Canonical routing:
            // - owner-result: payload.action = ACCEPT|DECLINE  -> owner-result info modal (Close only)
            // - invitee-invite: payload.actions[] present       -> invitee modal (Accept/Decline)
            //
            // Everything else is ignored.
            final payloadType = (payloadMap['type'] ?? '').toString();

            if (kDebugMode) {
              debugPrint(
                '[INBOX] insert delivery parsed type=$payloadType payloadKeys=${payloadMap.keys.toList()}',
              );
              if (payloadType.trim().isEmpty) {
                debugPrint(
                  '[INBOX] insert delivery has empty payloadType payloadRawType=${payloadRaw.runtimeType} rowKeys=${newRow.keys.toList()}',
                );
              }
            }
            if (payloadType.isNotEmpty &&
                payloadType != 'PLAN_INTERNAL_INVITE' &&
                payloadType != 'PLAN_MEMBER_LEFT') {
              return;
            }

            // ✅ Separate layer: PLAN_MEMBER_LEFT -> in-app info modal (foreground).
            if (payloadType == 'PLAN_MEMBER_LEFT') {
              final planId = (payloadMap['plan_id'] ??
                      payloadMap['planId'] ??
                      newRow['plan_id'] ??
                      newRow['planId'] ??
                      '')
                  .toString();
              final leftUserId = (payloadMap['left_user_id'] ??
                      payloadMap['leftUserId'] ??
                      payloadMap['left_userId'] ??
                      '')
                  .toString();
              if (planId.isEmpty || leftUserId.isEmpty) return;

              
final title = (payloadMap['title'] ?? '').toString();
final body = (payloadMap['body'] ?? '').toString();
final leftNickname = (payloadMap['left_nickname'] ??
        payloadMap['leftNickname'] ??
        '')
    .toString();
final planTitle = (payloadMap['plan_title'] ??
        payloadMap['planTitle'] ??
        '')
    .toString();

if (kDebugMode) {
  debugPrint(
    '[INBOX] plan-member-left insert planId=$planId leftUserId=$leftUserId',
  );
}

final cleanLeftNickname =
    leftNickname.trim().isEmpty ? null : leftNickname.trim();
final cleanPlanTitle =
    planTitle.trim().isEmpty ? null : planTitle.trim();
final cleanTitle = title.trim().isEmpty ? null : title.trim();

final bodyTrim = body.trim();
final cleanBody =
    (bodyTrim.isEmpty || bodyTrim == 'Один из участников покинул план.')
        ? null
        : bodyTrim;

PlanMemberLeftUiCoordinator.instance.enqueue(
  PlanMemberLeftUiRequest(
    planId: planId,
    leftUserId: leftUserId,
    leftNickname: cleanLeftNickname,
    planTitle: cleanPlanTitle,
    title: cleanTitle,
    body: cleanBody,
    source: PlanMemberLeftUiSource.foreground,
  ),
);
return;
            }

final ownerAction =
                (payloadMap['action'] ?? payloadMap['owner_action'] ?? '')
                    .toString()
                    .trim()
                    .toUpperCase();
            final isOwnerResult =
                ownerAction == 'ACCEPT' || ownerAction == 'DECLINE';

            final actionsRaw = payloadMap['actions'];
            final isInviteWithActions =
                actionsRaw is List && actionsRaw.isNotEmpty;

            if (!isOwnerResult && !isInviteWithActions) {
              return;
            }

            final inviteId = (payloadMap['invite_id'] ??
                    payloadMap['inviteId'] ??
                    newRow['invite_id'] ??
                    newRow['inviteId'] ??
                    '')
                .toString();
            final planId = (payloadMap['plan_id'] ??
                    payloadMap['planId'] ??
                    newRow['plan_id'] ??
                    newRow['planId'] ??
                    '')
                .toString();

            if (inviteId.isEmpty || planId.isEmpty) return;

            final title = (payloadMap['title'] ?? '').toString();
            final body = (payloadMap['body'] ?? '').toString();

            if (isOwnerResult) {
              final computedTitle = ownerAction == 'ACCEPT'
                  ? 'Приглашение принято'
                  : 'Приглашение отклонено';

              if (kDebugMode) {
                debugPrint(
                  '[INBOX] owner-result insert inviteId=$inviteId planId=$planId action=$ownerAction',
                );
              }

              InviteUiCoordinator.instance.enqueueOwnerResult(
                OwnerResultUiRequest(
                  inviteId: inviteId,
                  planId: planId,
                  action: ownerAction,
                  title: title.isEmpty ? computedTitle : title,
                  body: body,
                  source: InviteUiSource.foreground,
                ),
              );
              return;
            }

            // invitee-invite
            if (payloadMap.containsKey('action')) return;

            final actionToken =
                (payloadMap['action_token'] ?? payloadMap['actionToken'] ?? '')
                    .toString();

            if (kDebugMode) {
              debugPrint(
                '[INBOX] invite insert inviteId=$inviteId planId=$planId payloadType=$payloadType',
              );
            }

            InviteUiCoordinator.instance.enqueue(
              InviteUiRequest(
                inviteId: inviteId,
                planId: planId,
                title: title.isEmpty ? kInviteDialogDefaultTitle : title,
                body: body,
                actionToken: actionToken.isEmpty ? null : actionToken,
                source: InviteUiSource.foreground,
              ),
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[INBOX] handler error: $e');
            }
          }
        },
      );

      _inboxInvitesChannel = channel;
      channel.subscribe((status, [error]) {
        _inboxInvitesLastStatus = status;
        if (kDebugMode) {
          debugPrint('[INBOX] realtime status=$status error=$error');
        }

        if (status == RealtimeSubscribeStatus.subscribed) {
          _resetInboxInvitesRealtimeRetry();
          return;
        }

        // If channel closes/errors/times out, schedule retry (single-timer, no thrash).
        if (status == RealtimeSubscribeStatus.closed ||
            status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            error != null) {
          _scheduleInboxInvitesRealtimeRetry(
            reason: 'subscribe_status_$status',
            error: error,
          );
        }
      });
    } finally {
      _inboxInvitesEnsureInProgress = false;
      if (_inboxInvitesEnsureRerunRequested) {
        _inboxInvitesEnsureRerunRequested = false;
        unawaited(_ensureInboxInvitesRealtimeSubscribed());
      }
    }
  }

  void _resetInboxInvitesRealtimeRetry() {
    _inboxInvitesRealtimeRetryAttempt = 0;
    _inboxInvitesRealtimeRetryTimer?.cancel();
    _inboxInvitesRealtimeRetryTimer = null;
  }

  void _scheduleInboxInvitesRealtimeRetry({
    required String reason,
    Object? error,
  }) {
    // Single active timer: do not stack and do not thrash on rapid status flaps.
    if (_inboxInvitesRealtimeRetryTimer != null) return;

    _inboxInvitesRealtimeRetryAttempt += 1;
    final attempt = _inboxInvitesRealtimeRetryAttempt;

    // Exponential backoff: 300ms, 600ms, 1200ms, 2400ms, 4800ms (cap 5000ms).
    var delayMs = 300;
    for (var i = 1; i < attempt; i++) {
      delayMs *= 2;
      if (delayMs >= 5000) {
        delayMs = 5000;
        break;
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[INBOX] schedule retry in ${delayMs}ms (attempt=$attempt) reason=$reason error=$error',
      );
    }

    _inboxInvitesRealtimeRetryTimer =
        Timer(Duration(milliseconds: delayMs), () {
      // Mark timer as consumed before running ensure() so status flaps can schedule next one.
      _inboxInvitesRealtimeRetryTimer = null;

      if (_restoring) return;
      if (!_appShellReady) return;
      unawaited(_ensureInboxInvitesRealtimeSubscribed());
    });
  }

  Future<void> _disposeInboxInvitesRealtimeSubscription({
    bool resetRetry = true,
  }) async {
    final ch = _inboxInvitesChannel;
    _inboxInvitesChannel = null;
    _inboxInvitesChannelUserId = null;
    _inboxInvitesLastStatus = null;

    // Always stop any pending retry timer. Optionally keep attempt counter for backoff continuity.
    _inboxInvitesRealtimeRetryTimer?.cancel();
    _inboxInvitesRealtimeRetryTimer = null;
    if (resetRetry) {
      _inboxInvitesRealtimeRetryAttempt = 0;
    }

    if (ch == null) return;

    try {
      await _supabase.removeChannel(ch);
    } catch (_) {
      // ignore dispose errors
    }
  }

  Future<void> _handleInternalInviteAction({
    required String inviteId,
    required String planId,
    required String action,
    String? actionToken,
  }) async {
    if (_processingInviteAction) {
      if (kDebugMode) {
        debugPrint(
            '[InviteAction] ignored: already processing inviteId=$inviteId action=$action');
      }
      return;
    }

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      if (kDebugMode) {
        debugPrint(
            '[InviteAction] ignored: userId missing inviteId=$inviteId action=$action');
      }
      return;
    }

    _processingInviteAction = true;
    try {
      if (kDebugMode) {
        debugPrint(
            '[InviteAction] rpc start inviteId=$inviteId action=$action planId=$planId userId=$userId');
      }

      await _supabase.rpc(
        'respond_plan_internal_invite_v1',
        params: {
          'p_app_user_id': userId,
          'p_invite_id': inviteId,
          'p_action': action,
        },
      );

      if (kDebugMode) {
        debugPrint(
            '[InviteAction] rpc success inviteId=$inviteId action=$action planId=$planId appShell=$_appShellReady');
      }

      if (action == 'ACCEPT') {
        if (kDebugMode) {
          debugPrint(
              '[InviteAction] queue open details inviteId=$inviteId planId=$planId');
        }
        _queuePendingPlanOpen(
          planId,
          toastMessage: kInviteAcceptedToast,
        );
      } else if (action == 'DECLINE') {
        final toastCtx = App.navigatorKey.currentContext;
        if (toastCtx != null) {
          unawaited(showCenterToast(toastCtx, message: kInviteDeclinedToast));
        }
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[InviteAction] PostgrestException inviteId=$inviteId action=$action message=${e.message}');
      }
      final toastCtx = App.navigatorKey.currentContext;
      if (toastCtx != null) {
        unawaited(showCenterToast(toastCtx, message: e.message, isError: true));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[InviteAction] error inviteId=$inviteId action=$action error=$e');
      }
      final toastCtx = App.navigatorKey.currentContext;
      if (toastCtx != null) {
        unawaited(
            showCenterToast(toastCtx, message: 'Ошибка: $e', isError: true));
      }
    } finally {
      _processingInviteAction = false;
    }
  }

  Future<void> _openPlanDetailsFromCurrentShell(
    String planId, {
    String? toastMessage,
  }) async {
    final userId = _userId;
    if (kDebugMode) {
      debugPrint(
          '[InviteNav] open details requested planId=$planId userId=$userId');
    }
    if (userId == null || userId.isEmpty) return;

    final nav = App.navigatorKey.currentState;
    if (nav == null) return;

    final PlansRepository repo = PlansRepositoryImpl(Supabase.instance.client);

    Route<T> noAnimRoute<T>(Widget child) {
      return PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

    nav.push(
      noAnimRoute(
        PlansScreen(appUserId: userId),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav2 = App.navigatorKey.currentState;
      if (nav2 == null) return;

      unawaited(() async {
        final changed = await nav2.push<bool>(
          MaterialPageRoute(
            builder: (_) => PlanDetailsScreen(
              appUserId: userId,
              planId: planId,
              repository: repo,
            ),
          ),
        );

        if (kDebugMode) {
          debugPrint(
              '[InviteNav] PlanDetails popped changed=$changed planId=$planId');
        }

        // If the user left/deleted the plan inside details (server-confirmed),
        // force-refresh the Plans screen snapshot so a "dead" card cannot linger.
        if (changed == true) {
          final nav3 = App.navigatorKey.currentState;
          if (nav3 == null) return;

          // We are now back on PlansScreen (PlanDetails popped). Replace the route
          // with a fresh instance to trigger canonical refetch in initState.
          nav3.pushReplacement(
            noAnimRoute(
              PlansScreen(appUserId: userId),
            ),
          );
        }
      }());

      if (toastMessage != null && toastMessage.isNotEmpty) {
        Future<void>.delayed(const Duration(milliseconds: 350), () async {
          final toastCtx = App.navigatorKey.currentContext;
          if (toastCtx == null) return;
          await showCenterToast(toastCtx, message: toastMessage);
        });
      }
    });
  }

  void _queuePendingPlanOpen(
    String planId, {
    String? toastMessage,
  }) {
    if (kDebugMode) {
      debugPrint(
          '[InviteNav] queue plan open planId=$planId toast=$toastMessage');
    }
    if (mounted) {
      setState(() {
        _pendingOpenPlanId = planId;
        _pendingOpenPlanToastMessage = toastMessage;
      });
    } else {
      _pendingOpenPlanId = planId;
      _pendingOpenPlanToastMessage = toastMessage;
    }

    _schedulePendingPlanOpenIfReady();
  }

  void _schedulePendingPlanOpenIfReady() {
    final planId = _pendingOpenPlanId;
    if (planId == null || planId.isEmpty) return;
    if (_restoring) return;
    if (!_appShellReady) return;

    _pendingPlanOpenTimer?.cancel();

    final toastMessage = _pendingOpenPlanToastMessage;

    if (mounted) {
      setState(() {
        _pendingOpenPlanId = null;
        _pendingOpenPlanToastMessage = null;
      });
    } else {
      _pendingOpenPlanId = null;
      _pendingOpenPlanToastMessage = null;
    }

    unawaited(
      _openPlanDetailsFromCurrentShell(
        planId,
        toastMessage: toastMessage,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(GeoService.instance.refresh());
      unawaited(_ensureDeviceTokenRegistered());

      // If user restored while app was backgrounded, flush pending invite UI/actions.
            _schedulePendingPlanOpenIfReady();
    }
  }

  void _initAuthListener() {
    _authSub = _supabase.auth.onAuthStateChange.listen((_) {
      _restore();
    });
  }

  Future<void> _initDeepLinks() async {
    // initial link (cold start)
    final initialUri = await _appLinks.getInitialLink();
    await _handleIncomingUri(initialUri);

    // stream (while app is running)
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      unawaited(_handleIncomingUri(uri));
    });
  }

  void _initFcmTokenRefresh() {
    if (kIsWeb) return;

    _fcmTokenSub?.cancel();

    _fcmTokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_registerDeviceToken(token));
    });
  }

  Future<void> _handleIncomingUri(Uri? uri) async {
    if (uri == null) return;

    final token = _extractPlanInviteToken(uri);
    if (token == null || token.isEmpty) return;

    await _storage.writePendingPlanInviteToken(token);
    unawaited(_tryConsumePendingPlanInvite());
  }

  String? _extractPlanInviteToken(Uri uri) {
    final path = uri.path.toLowerCase();
    final qp = uri.queryParameters;

    final looksLikePlanInvitePath =
        path.contains('plan-invite') || path.contains('plan_invite');

    final tokenFromDedicatedParam =
        qp['plan_invite_token'] ?? qp['planInviteToken'] ?? qp['invite_token'];

    if (looksLikePlanInvitePath) {
      return qp['token'] ?? tokenFromDedicatedParam;
    }

    if (tokenFromDedicatedParam != null && tokenFromDedicatedParam.isNotEmpty) {
      return tokenFromDedicatedParam;
    }

    return null;
  }

  Future<void> _tryConsumePendingPlanInvite() async {
    if (_handlingPendingPlanInvite) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    _handlingPendingPlanInvite = true;
    try {
      final token = await _storage.readPendingPlanInviteToken();
      if (token == null || token.isEmpty) return;

      final res = await _supabase.rpc('use_plan_invite_v1', params: {
        'p_app_user_id': userId,
        'p_token': token,
      });

      final planId = res?.toString();
      if (planId == null || planId.isEmpty) {
        await _storage.clearPendingPlanInviteToken();
        return;
      }

      await _storage.clearPendingPlanInviteToken();

      _queuePendingPlanOpen(planId);

      await _restore();
    } on PostgrestException catch (e) {
      await _storage.clearPendingPlanInviteToken();

      if (!mounted) return;
      unawaited(showCenterToast(context, message: e.message, isError: true));
    } catch (e) {
      await _storage.clearPendingPlanInviteToken();

      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Ошибка инвайта: $e')),
      );
    } finally {
      _handlingPendingPlanInvite = false;
    }
  }

  // =========================
  // FCM -> server registration
  // =========================

  String? _platformString() {
    if (kIsWeb) return null;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  void _runPostIdentityFlows() {
    if (_postIdentityFlowsRunning) {
      _postIdentityFlowsRerunRequested = true;
      return;
    }

    _postIdentityFlowsRunning = true;
    unawaited(_runPostIdentityFlowsAsync());
  }

  Future<void> _runPostIdentityFlowsAsync() async {
    try {
      // After identity becomes available (AUTH/GUEST/onboarding), kick off pending UI-only flows.
      await _ensureDeviceTokenRegistered();
      await _tryConsumePendingPlanInvite();
            _schedulePendingPlanOpenIfReady();
    } finally {
      _postIdentityFlowsRunning = false;
      if (_postIdentityFlowsRerunRequested) {
        _postIdentityFlowsRerunRequested = false;
        _runPostIdentityFlows();
      }
    }
  }

  Future<void> _ensureDeviceTokenRegistered() async {
    if (kIsWeb) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    final platform = _platformString();
    if (platform == null) return;

    if (_registeringDeviceToken) {
      _registerDeviceTokenRetryRequested = true;
      return;
    }
    _registeringDeviceToken = true;

    try {
      if (platform == 'ios') {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;

      await _registerDeviceToken(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] ensureDeviceTokenRegistered error: $e');
      }
    } finally {
      _registeringDeviceToken = false;
      if (_registerDeviceTokenRetryRequested) {
        _registerDeviceTokenRetryRequested = false;
        unawaited(_ensureDeviceTokenRegistered());
      }
    }
  }

  Future<void> _registerDeviceToken(String token) async {
    if (kIsWeb) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    final platform = _platformString();
    if (platform == null) return;

    final t = token.trim();
    if (t.isEmpty) return;

    final dedupeKey = '$userId|$platform|$t';
    if (_lastRegisteredDeviceTokenKey == dedupeKey) return;
    _lastRegisteredDeviceTokenKey = dedupeKey;

    try {
      await _supabase.rpc(
        'upsert_device_token_v1',
        params: {
          'p_app_user_id': userId,
          'p_platform': platform,
          'p_token': t,
        },
      );

      if (kDebugMode) {
        debugPrint('[FCM] token registered for $platform appUserId=$userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] token register failed: $e');
      }
      if (_lastRegisteredDeviceTokenKey == dedupeKey) {
        _lastRegisteredDeviceTokenKey = null;
      }
    }
  }

  Future<void> _restore() async {
    _retryTimer?.cancel();
    _pendingPlanOpenTimer?.cancel();

    final session = _supabase.auth.currentSession;

    // ===== USER =====
    if (session != null) {
      final res = await _supabase.rpc('current_user');

      if (res is Map) {
        final row = Map<String, dynamic>.from(res);

        await _storage.clear();

        if (!mounted) return;

        if (_inboxInvitesChannelUserId != (row['id'] as String)) {
          await _disposeInboxInvitesRealtimeSubscription();
        }
        setState(() {
          _userId = row['id'] as String;
          _nickname = row['nickname'] as String? ?? '';
          _publicId = row['public_id'] as String;
          _email = row['email'] as String?;
          _restoring = false;
          _appShellReady = false;
          _homeVisibleAt = null;
          _postIdentityFlowsRerunRequested = false;
        });
        InviteUiCoordinator.instance.setRootUiReady(false);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);

        _runPostIdentityFlows();
        return;
      }

      _retryTimer = Timer(const Duration(milliseconds: 400), _restore);
      return;
    }

    // ===== GUEST =====
    final snapshot = await _storage.read();
    if (snapshot != null && snapshot.state == 'GUEST') {
      if (!mounted) return;
      if (_inboxInvitesChannelUserId != snapshot.id) {
        await _disposeInboxInvitesRealtimeSubscription();
      }
      setState(() {
        _userId = snapshot.id;
        _nickname = snapshot.nickname;
        _publicId = snapshot.publicId;
        _email = null;
        _restoring = false;
        _appShellReady = false;
        _homeVisibleAt = null;
        _postIdentityFlowsRerunRequested = false;
      });
      InviteUiCoordinator.instance.setRootUiReady(false);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);

      _runPostIdentityFlows();
      return;
    }

    // ===== ONBOARDING =====
    if (!mounted) return;
    await _disposeInboxInvitesRealtimeSubscription();
    setState(() {
      _userId = null;
      _nickname = null;
      _publicId = null;
      _email = null;
      _restoring = false;
      _appShellReady = false;
      _homeVisibleAt = null;
      _postIdentityFlowsRerunRequested = false;
    });
    InviteUiCoordinator.instance.setRootUiReady(false);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);
  }

  void _finishOnboarding(Map<String, dynamic> result) {
    unawaited(_finishOnboardingAsync(result));
  }

  Future<void> _finishOnboardingAsync(Map<String, dynamic> result) async {
    final userId = result['id'] as String?;
    final publicId = result['public_id'] as String?;
    final nickname = result['nickname'] as String?;
    final state = result['state'] as String?;

    if (userId == null ||
        userId.isEmpty ||
        publicId == null ||
        publicId.isEmpty ||
        state == null) {
      throw StateError('Invalid bootstrap_guest payload: $result');
    }

    final snapshot = UserSnapshot(
      id: userId,
      publicId: publicId,
      nickname: nickname ?? '',
      state: state,
    );

    await _storage.save(snapshot);

    if (!mounted) return;
    setState(() {
      _userId = snapshot.id;
      _publicId = snapshot.publicId;
      _nickname = snapshot.nickname;
      _email = null;
      _appShellReady = false;
      _homeVisibleAt = null;
    });
    InviteUiCoordinator.instance.setRootUiReady(false);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(false);

    _runPostIdentityFlows();
  }

  void _onAppShellReady() {
    if (_appShellReady) return;
    _appShellReady = true;
    InviteUiCoordinator.instance.setRootUiReady(true);
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(true);

    _ensureInboxInvitesRealtimeSubscribed();

    _homeVisibleAt ??= DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schedulePendingPlanOpenIfReady();
          });
  }

  void _consumePendingOpenPlanId() {
    if (_pendingOpenPlanId == null && _pendingOpenPlanToastMessage == null) {
      return;
    }
    setState(() {
      _pendingOpenPlanId = null;
      _pendingOpenPlanToastMessage = null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _pendingPlanOpenTimer?.cancel();
    _authSub?.cancel();
    _linkSub?.cancel();
    _fcmTokenSub?.cancel();
    _fcmMessageSub?.cancel();
    _disposeInboxInvitesRealtimeSubscription();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userId != null && _publicId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _schedulePendingPlanOpenIfReady();
      });

      return HomeScreen(
        userId: _userId!,
        nickname: _nickname ?? '',
        publicId: _publicId!,
        email: _email,
        initialPlanIdToOpen: null,
        onInitialPlanOpened: _consumePendingOpenPlanId,
        onAppShellReady: _onAppShellReady,
      );
    }

    return NicknameScreen(
      onBootstrapped: _finishOnboarding,
    );
  }
}