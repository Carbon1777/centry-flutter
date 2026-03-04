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
import '../ui/friends/friends_refresh_bus.dart';
import 'invite_ui_coordinator.dart';
import 'plan_member_left_ui_coordinator.dart';
import 'plan_member_removed_ui_coordinator.dart';
import 'plan_deleted_ui_coordinator.dart';
import 'plan_member_joined_by_invite_ui_coordinator.dart';
import '../data/friends/friends_repository_impl.dart';

/// Canonical width constraints for Friends modals (keep consistent across all FRIEND_* dialogs).
const BoxConstraints _kFriendDialogConstraints =
    BoxConstraints(minWidth: 280, maxWidth: 520);

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
  static const String kInviteDialogDefaultTitle = 'Вас пригласили в план';
  static const String kInviteAcceptedToast = 'Приглашение принято';
  static const String kFriendRequestDefaultTitle = 'Запрос в друзья';
  static const String kFriendRequestAcceptedTitle = 'Запрос принят';
  static const String kFriendRequestDeclinedTitle = 'Запрос отклонён';
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

  // Pending friend request UI events (when app opens from notification before shell is ready)
  final List<Map<String, dynamic>> _pendingFriendRequests =
      <Map<String, dynamic>>[];
  // Pending friend OPEN intents (Scenario B/C): resolve via INBOX once identity + shell are ready.
  final List<Map<String, dynamic>> _pendingFriendOpenIntents =
      <Map<String, dynamic>>[];
  // Pending consume requests when delivery arrives before shell is ready.
  final List<String> _pendingConsumeDeliveryIds = <String>[];
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

    PlanMemberRemovedUiCoordinator.instance
        .attachNavigatorKey(App.navigatorKey);
    PlanMemberRemovedUiCoordinator.instance.setRootUiReady(false);

    PlanDeletedUiCoordinator.instance.attachNavigatorKey(App.navigatorKey);
    PlanDeletedUiCoordinator.instance.setRootUiReady(false);

    PlanMemberJoinedByInviteUiCoordinator.instance
        .attachNavigatorKey(App.navigatorKey);
    PlanMemberJoinedByInviteUiCoordinator.instance.setRootUiReady(false);

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
                // Canon: on tap "Посмотреть" we must build UI from PENDING INBOX (source of truth),
                // then ACK/consume after enqueue/show to prevent late PUSH duplicates.
                final pending =
                    await _loadPendingOwnerInviteResultInboxByInviteId(
                        inviteId);
                if (pending != null) {
                  final pendingAction = (pending['action'] ??
                          pending['owner_action'] ??
                          pending['ownerAction'] ??
                          '')
                      .toString()
                      .trim()
                      .toUpperCase();

                  final effectiveAction =
                      (pendingAction == 'ACCEPT' || pendingAction == 'DECLINE')
                          ? pendingAction
                          : (actionValue == 'ACCEPT' ? 'ACCEPT' : 'DECLINE');

                  final pendingPlanId =
                      (pending['plan_id'] ?? pending['planId'] ?? planId)
                          .toString();
                  final pendingTitleRaw = (pending['title'] ?? '').toString();
                  final pendingTitle = pendingTitleRaw.trim().isEmpty
                      ? (effectiveAction == 'ACCEPT'
                          ? 'Приглашение принято'
                          : 'Приглашение отклонено')
                      : pendingTitleRaw;
                  final pendingBody = (pending['body'] ?? body).toString();

                  InviteUiCoordinator.instance.enqueueOwnerResult(
                    OwnerResultUiRequest(
                      inviteId: inviteId,
                      planId: pendingPlanId,
                      action: effectiveAction,
                      title: pendingTitle,
                      body: pendingBody,
                      source: InviteUiSource.backgroundIntent,
                    ),
                  );

                  final deliveryId =
                      (pending['delivery_id'] ?? pending['deliveryId'] ?? '')
                          .toString();
                  _scheduleConsumeInboxDelivery(deliveryId);
                  return;
                }

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

        final type = (extras['type'] ??
                extras['kind'] ??
                payload['type'] ??
                payload['kind'] ??
                '')
            .toString();
        final planId =
            (extras['plan_id'] ?? payload['plan_id'] ?? payload['planId'] ?? '')
                .toString();
        if (type == 'PLAN_INTERNAL_INVITE' && planId.isNotEmpty) {
          // Canon: tap on invite body does nothing (no ACCEPT/DECLINE, no nav).
          return;
        }

// PLAN_MEMBER_REMOVED: show in-app info modal using server-provided payload/extras.
        if (type == 'PLAN_MEMBER_REMOVED') {
          // payload from extras['payload'] OR flattened extras keys (FCM sometimes flattens).
          final payloadType = (payload['type'] ??
                  payload['kind'] ??
                  extras['type'] ??
                  extras['kind'] ??
                  '')
              .toString()
              .trim();
          if (payloadType == 'PLAN_MEMBER_REMOVED') {
            final removedPlanId = (payload['plan_id'] ??
                    payload['planId'] ??
                    extras['plan_id'] ??
                    extras['planId'] ??
                    '')
                .toString();
            final removedUserId = (payload['removed_user_id'] ??
                    payload['removedUserId'] ??
                    extras['removed_user_id'] ??
                    extras['removedUserId'] ??
                    '')
                .toString();
            final ownerUserId = (payload['owner_user_id'] ??
                    payload['ownerUserId'] ??
                    extras['owner_user_id'] ??
                    extras['ownerUserId'] ??
                    '')
                .toString();

            if (removedPlanId.isNotEmpty &&
                removedUserId.isNotEmpty &&
                ownerUserId.isNotEmpty) {
              final ownerNickname = (payload['owner_nickname'] ??
                      payload['ownerNickname'] ??
                      extras['owner_nickname'] ??
                      extras['ownerNickname'] ??
                      '')
                  .toString()
                  .trim();
              final planTitle = (payload['plan_title'] ??
                      payload['planTitle'] ??
                      extras['plan_title'] ??
                      extras['planTitle'] ??
                      '')
                  .toString()
                  .trim();
              final title =
                  (payload['title'] ?? extras['title'] ?? '').toString().trim();
              final body =
                  (payload['body'] ?? extras['body'] ?? '').toString().trim();

              PlanMemberRemovedUiCoordinator.instance.enqueue(
                PlanMemberRemovedUiRequest(
                  planId: removedPlanId,
                  removedUserId: removedUserId,
                  ownerUserId: ownerUserId,
                  ownerNickname: ownerNickname.isEmpty ? null : ownerNickname,
                  planTitle: planTitle.isEmpty ? null : planTitle,
                  title: title.isEmpty ? null : title,
                  body: body.isEmpty ? null : body,
                  source: PlanMemberRemovedUiSource.backgroundIntent,
                ),
              );
              final deliveryId = (payload['delivery_id'] ??
                      payload['deliveryId'] ??
                      extras['delivery_id'] ??
                      extras['deliveryId'] ??
                      '')
                  .toString();
              _scheduleConsumeInboxDelivery(deliveryId);

              return;
            }
          }
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
            final pending =
                await _loadPendingOwnerInviteResultInboxByInviteId(inviteId);
            if (pending != null) {
              final pType = (pending['type'] ?? '').toString().trim();
              final pendingAction = (pending['action'] ??
                      pending['owner_action'] ??
                      pending['ownerAction'] ??
                      '')
                  .toString()
                  .trim()
                  .toUpperCase();

              final actionValue =
                  (pendingAction == 'ACCEPT' || pendingAction == 'DECLINE')
                      ? pendingAction
                      : (pType == 'PLAN_INTERNAL_INVITE_ACCEPTED'
                          ? 'ACCEPT'
                          : 'DECLINE');

              final pendingPlanId =
                  (pending['plan_id'] ?? pending['planId'] ?? planId)
                      .toString();
              final pendingTitleRaw = (pending['title'] ?? '').toString();
              final pendingTitle = pendingTitleRaw.trim().isEmpty
                  ? (actionValue == 'ACCEPT'
                      ? 'Приглашение принято'
                      : 'Приглашение отклонено')
                  : pendingTitleRaw;
              final pendingBody = (pending['body'] ?? body ?? '').toString();

              InviteUiCoordinator.instance.enqueueOwnerResult(
                OwnerResultUiRequest(
                  inviteId: inviteId,
                  planId: pendingPlanId,
                  action: actionValue,
                  title: pendingTitle,
                  body: pendingBody,
                  source: InviteUiSource.backgroundIntent,
                ),
              );

              final deliveryId =
                  (pending['delivery_id'] ?? pending['deliveryId'] ?? '')
                      .toString();
              _scheduleConsumeInboxDelivery(deliveryId);
              return;
            }

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
      onFriendOpen: ({
        required String type,
        String? eventId,
        String? requestId,
        String? title,
        String? body,
      }) async {
        // Scenario B/C: local notification OPEN -> resolve pending INBOX and show canonical UI.
        // If identity/shell isn't ready yet (cold start), stash intent and flush later.
        if (_restoring || !_appShellReady || (_userId ?? '').trim().isEmpty) {
          _enqueueFriendOpenIntent(
            type: type,
            eventId: eventId,
            requestId: requestId,
            title: title,
            body: body,
          );
          return;
        }

        await _handleFriendOpenFromLocalNotification(
          type: type,
          eventId: eventId,
          requestId: requestId,
          title: title,
          body: body,
        );
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
            leftNickname: (leftNickname ?? '').trim().isEmpty
                ? null
                : (leftNickname ?? '').trim(),
            planTitle: (planTitle ?? '').trim().isEmpty
                ? null
                : (planTitle ?? '').trim(),
            title: (title ?? '').trim().isEmpty ? null : (title ?? '').trim(),
            body: ((body ?? '').trim().isEmpty ||
                    (body ?? '').trim() == 'Один из участников покинул план.')
                ? null
                : (body ?? '').trim(),
            source: PlanMemberLeftUiSource.backgroundIntent,
          ),
        );
      },
      onPlanMemberJoinedByInviteOpen: ({
        required String planId,
        required String joinedUserId,
        String? joinedNickname,
        String? planTitle,
        String? title,
        String? body,
      }) async {
        PlanMemberJoinedByInviteUiCoordinator.instance.enqueue(
          PlanMemberJoinedByInviteUiRequest(
            planId: planId,
            joinedUserId: joinedUserId,
            joinedNickname: (joinedNickname ?? '').trim().isEmpty
                ? null
                : (joinedNickname ?? '').trim(),
            planTitle: (planTitle ?? '').trim().isEmpty
                ? null
                : (planTitle ?? '').trim(),
            title: (title ?? '').trim().isEmpty ? null : (title ?? '').trim(),
            body: (body ?? '').trim().isEmpty ? null : (body ?? '').trim(),
            source: PlanMemberJoinedByInviteUiSource.backgroundIntent,
          ),
        );
      },
      onPlanMemberRemovedOpen: ({
        required String planId,
        required String removedUserId,
        required String ownerUserId,
        String? ownerNickname,
        String? planTitle,
        String? title,
        String? body,
      }) async {
        PlanMemberRemovedUiCoordinator.instance.enqueue(
          PlanMemberRemovedUiRequest(
            planId: planId,
            removedUserId: removedUserId,
            ownerUserId: ownerUserId,
            ownerNickname: (ownerNickname ?? '').trim().isEmpty
                ? null
                : (ownerNickname ?? '').trim(),
            planTitle: (planTitle ?? '').trim().isEmpty
                ? null
                : (planTitle ?? '').trim(),
            title: (title ?? '').trim().isEmpty ? null : (title ?? '').trim(),
            body: (body ?? '').trim().isEmpty ? null : (body ?? '').trim(),
            source: PlanMemberRemovedUiSource.backgroundIntent,
          ),
        );
      },
      onPlanDeletedOpen: ({
        required String planId,
        required String ownerUserId,
        String? ownerNickname,
        String? planTitle,
        String? eventId,
        String? title,
        String? body,
      }) async {
        // ✅ Canon: B/C open should show the same modal; we reuse existing queue pattern.
        PlanDeletedUiCoordinator.instance.enqueue(
          PlanDeletedUiRequest(
            planId: planId,
            ownerUserId: ownerUserId,
            ownerNickname: (ownerNickname ?? '').trim().isEmpty
                ? null
                : (ownerNickname ?? '').trim(),
            planTitle: (planTitle ?? '').trim().isEmpty
                ? null
                : (planTitle ?? '').trim(),
            title: (title ?? '').trim().isEmpty ? null : (title ?? '').trim(),
            body: (body ?? '').trim().isEmpty ? null : (body ?? '').trim(),
            source: PlanDeletedUiSource.backgroundIntent,
          ),
        );
      },
    );
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

      // Friend requests: keep same canon as invites (data-only push -> local tray + in-app modal)
      await PushNotifications.showFriendRequest(m);

      // In-app modal is canonical. Queue it and show only after welcome/home phase.
      _queueInternalInviteDialogFromRemoteMessage(m);

      _queueFriendRequestDialogFromRemoteMessage(m);

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

  void _queueFriendRequestDialogFromRemoteMessage(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString().trim();
    if (t != 'FRIEND_REQUEST_RECEIVED' &&
        t != 'FRIEND_REQUEST_ACCEPTED' &&
        t != 'FRIEND_REQUEST_DECLINED') {
      return;
    }

    final requestId = (m.data['request_id'] ?? '').toString();
    final title = (m.data['title'] ?? m.notification?.title ?? '').toString();
    final body = (m.data['body'] ?? m.notification?.body ?? '').toString();

    final payloadMap = <String, dynamic>{
      'type': t,
      if (requestId.isNotEmpty) 'request_id': requestId,
      ...m.data,
      if (title.isNotEmpty) 'title': title,
      if (body.isNotEmpty) 'body': body,
    };

    _enqueueFriendRequestUi(payloadMap);
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
  }

  void _enqueueFriendRequestUi(Map<String, dynamic> payload) {
    // Show immediately if shell is ready, otherwise stash and flush after UI ready.
    if (_appShellReady) {
      unawaited(_handleFriendDeliveryPayload(payload));
      return;
    }
    _pendingFriendRequests.add(payload);
  }

  void _flushPendingFriendRequestsIfAny() {
    if (!_appShellReady) return;
    if (_pendingFriendRequests.isEmpty) return;
    final items = List<Map<String, dynamic>>.from(_pendingFriendRequests);
    _pendingFriendRequests.clear();
    for (final p in items) {
      unawaited(_handleFriendDeliveryPayload(p));
    }
  }

  void _enqueueFriendOpenIntent({
    required String type,
    String? eventId,
    String? requestId,
    String? title,
    String? body,
  }) {
    _pendingFriendOpenIntents.add(<String, dynamic>{
      'type': type,
      if (eventId != null && eventId.trim().isNotEmpty)
        'event_id': eventId.trim(),
      if (requestId != null && requestId.trim().isNotEmpty)
        'request_id': requestId.trim(),
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
    });
  }

  void _flushPendingFriendOpenIntentsIfAny() {
    if (!_appShellReady) return;
    if (_pendingFriendOpenIntents.isEmpty) return;

    final intents = List<Map<String, dynamic>>.from(_pendingFriendOpenIntents);
    _pendingFriendOpenIntents.clear();
    for (final i in intents) {
      final type = (i['type'] ?? '').toString().trim();
      if (type.isEmpty) continue;
      unawaited(
        _handleFriendOpenFromLocalNotification(
          type: type,
          eventId: (i['event_id'] ?? '').toString().trim().isEmpty
              ? null
              : (i['event_id'] ?? '').toString().trim(),
          requestId: (i['request_id'] ?? '').toString().trim().isEmpty
              ? null
              : (i['request_id'] ?? '').toString().trim(),
          title: (i['title'] ?? '').toString().trim().isEmpty
              ? null
              : (i['title'] ?? '').toString().trim(),
          body: (i['body'] ?? '').toString().trim().isEmpty
              ? null
              : (i['body'] ?? '').toString().trim(),
        ),
      );
    }
  }

  Map<String, dynamic> _asStringKeyedMap(Map raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      out[k.toString()] = v;
    });
    return out;
  }

  Future<Map<String, dynamic>?> _loadPendingOwnerInviteResultInboxByInviteId(
    String inviteId,
  ) async {
    final appUserId = _userId;
    final iid = inviteId.trim();
    if (appUserId == null || appUserId.trim().isEmpty) return null;
    if (iid.isEmpty) return null;

    try {
      final dynamic raw = await _supabase
          .from('notification_deliveries')
          .select('id,payload,created_at')
          .eq('user_id', appUserId)
          .eq('channel', 'INBOX')
          .eq('status', 'PENDING')
          .order('created_at', ascending: false)
          .limit(50);

      if (raw is! List) return null;

      for (final r in raw) {
        if (r is! Map) continue;
        final id = (r['id'] ?? '').toString().trim();
        final payloadRaw = r['payload'];
        if (id.isEmpty || payloadRaw is! Map) continue;

        final payload = _asStringKeyedMap(payloadRaw);
        final t = (payload['type'] ?? '').toString().trim();
        final action = (payload['action'] ??
                payload['owner_action'] ??
                payload['ownerAction'] ??
                '')
            .toString()
            .trim()
            .toUpperCase();

        final isOwnerResult = (t == 'PLAN_INTERNAL_INVITE' &&
                (action == 'ACCEPT' || action == 'DECLINE')) ||
            t == 'PLAN_INTERNAL_INVITE_ACCEPTED' ||
            t == 'PLAN_INTERNAL_INVITE_DECLINED';

        if (!isOwnerResult) {
          continue;
        }

        // Backward compatibility: older payloads used separate types without explicit action.
        if ((payload['action'] == null ||
                payload['action'].toString().trim().isEmpty) &&
            (t == 'PLAN_INTERNAL_INVITE_ACCEPTED' ||
                t == 'PLAN_INTERNAL_INVITE_DECLINED')) {
          payload['action'] =
              t == 'PLAN_INTERNAL_INVITE_ACCEPTED' ? 'ACCEPT' : 'DECLINE';
        }

        final payloadInviteId =
            (payload['invite_id'] ?? payload['inviteId'] ?? '')
                .toString()
                .trim();
        if (payloadInviteId != iid) continue;

        payload['delivery_id'] = id;
        return payload;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPendingFriendInboxDelivery({
    required String type,
    String? eventId,
    String? requestId,
  }) async {
    final appUserId = _userId;
    if (appUserId == null || appUserId.trim().isEmpty) return null;

    final t = type.trim();
    if (t.isEmpty || !t.startsWith('FRIEND_')) return null;

    final eid = (eventId ?? '').trim();
    final rid = (requestId ?? '').trim();

    try {
      // Best correlation: event_id is stable (notification_deliveries.event_id).
      if (eid.isNotEmpty) {
        final dynamic raw = await _supabase
            .from('notification_deliveries')
            .select('id,event_id,payload,created_at')
            .eq('user_id', appUserId)
            .eq('channel', 'INBOX')
            .eq('status', 'PENDING')
            .eq('event_id', eid)
            .order('created_at', ascending: false)
            .limit(1);

        if (raw is List && raw.isNotEmpty) {
          final r = raw.first;
          if (r is Map) {
            final id = (r['id'] ?? '').toString().trim();
            final payloadRaw = r['payload'];
            if (id.isNotEmpty && payloadRaw is Map) {
              final payload = _asStringKeyedMap(payloadRaw);
              final payloadType = (payload['type'] ?? '').toString().trim();
              if (payloadType == t) {
                payload['delivery_id'] = id;
                payload['event_id'] = (r['event_id'] ?? eid).toString();
                return payload;
              }
            }
          }
        }
      }

      // Fallback: scan recent pending INBOX deliveries by type (+ request_id if provided).
      final dynamic raw = await _supabase
          .from('notification_deliveries')
          .select('id,event_id,payload,created_at')
          .eq('user_id', appUserId)
          .eq('channel', 'INBOX')
          .eq('status', 'PENDING')
          .order('created_at', ascending: false)
          .limit(50);

      if (raw is! List) return null;

      for (final r in raw) {
        if (r is! Map) continue;
        final id = (r['id'] ?? '').toString().trim();
        final payloadRaw = r['payload'];
        if (id.isEmpty || payloadRaw is! Map) continue;

        final payload = _asStringKeyedMap(payloadRaw);
        final payloadType = (payload['type'] ?? '').toString().trim();
        if (payloadType != t) continue;

        if (rid.isNotEmpty) {
          final pr = (payload['request_id'] ?? payload['requestId'] ?? '')
              .toString()
              .trim();
          if (pr != rid) continue;
        }

        payload['delivery_id'] = id;
        final rowEventId = (r['event_id'] ?? '').toString().trim();
        if (rowEventId.isNotEmpty) payload['event_id'] = rowEventId;
        return payload;
      }
    } catch (_) {
      // ignore
    }

    return null;
  }

  Future<void> _handleFriendOpenFromLocalNotification({
    required String type,
    String? eventId,
    String? requestId,
    String? title,
    String? body,
  }) async {
    // Canon: build UI from INBOX (source of truth).
    final resolved = await _loadPendingFriendInboxDelivery(
      type: type,
      eventId: eventId,
      requestId: requestId,
    );

    if (resolved != null) {
      _enqueueFriendRequestUi(resolved);
      _flushPendingFriendRequestsIfAny();
      return;
    }

    // If we couldn't correlate, do NOT consume anything.
    if (kDebugMode) {
      debugPrint(
        '[Friends] open-from-local-notif: no pending INBOX found type=$type eventId=$eventId requestId=$requestId',
      );
    }

    final ctx = App.navigatorKey.currentContext;
    if (ctx != null) {
      await showCenterToast(
        ctx,
        message: (title ?? '').trim().isNotEmpty
            ? (title ?? '').trim()
            : 'Откройте вкладку “Друзья”',
        isError: false,
      );
    }
    FriendsRefreshBus.ping();
  }

  String _quoteNick(String nick) {
    final t = nick.trim();
    if (t.isEmpty) return '';
    // Avoid double quoting.
    if (t.startsWith('«') && t.endsWith('»')) return t;
    return '«$t»';
  }

  String _ensureNickQuotedInText(String text, String nick) {
    final t = text.trim();
    final n = nick.trim();
    if (t.isEmpty || n.isEmpty) return t;
    final quoted = _quoteNick(n);

    // If already contains quoted nick, keep as is.
    if (t.contains(quoted)) return t;

    // Replace raw nick occurrences with quoted variant.
    return t.replaceAll(n, quoted);
  }

  Future<void> _consumeInboxDeliveryIfPossibleFromPayload(
      Map<String, dynamic> payload) async {
    final deliveryId =
        (payload['delivery_id'] ?? payload['deliveryId'] ?? payload['id'] ?? '')
            .toString()
            .trim();
    if (deliveryId.isEmpty) return;
    await _consumeInboxDelivery(deliveryId: deliveryId);
  }

  Future<void> _handleFriendDeliveryPayload(
      Map<String, dynamic> payload) async {
    final type = (payload['type'] ?? '').toString().trim();
    if (type.isEmpty) return;

    if (type == 'FRIEND_REQUEST_RECEIVED') {
      final requestId = (payload['request_id'] ?? '').toString().trim();
      final fromName =
          (payload['from_display_name'] ?? payload['fromDisplayName'] ?? '')
              .toString()
              .trim();
      final title = (payload['title'] ?? '').toString().trim();
      final rawBody = (payload['body'] ?? '').toString().trim();

      final computedBody = rawBody.isNotEmpty
          ? (fromName.isNotEmpty
              ? _ensureNickQuotedInText(rawBody, fromName)
              : rawBody)
          : (fromName.isNotEmpty
              ? '${_quoteNick(fromName)} отправил запрос в друзья.'
              : 'Новый запрос в друзья.');

      await _showFriendRequestReceivedDialog(
        title: title.isEmpty ? kFriendRequestDefaultTitle : title,
        body: computedBody,
        requestId: requestId,
      );

      // ✅ ACK/consume строго после реального UI (dialog shown and dismissed)
      await _consumeInboxDeliveryIfPossibleFromPayload(payload);
      return;
    }

    if (type == 'FRIEND_REQUEST_ACCEPTED' ||
        type == 'FRIEND_REQUEST_DECLINED') {
      final friendName =
          (payload['friend_display_name'] ?? payload['friendDisplayName'] ?? '')
              .toString()
              .trim();
      final title = (payload['title'] ?? '').toString().trim();
      final rawBody = (payload['body'] ?? '').toString().trim();

      final isAccepted = type == 'FRIEND_REQUEST_ACCEPTED';
      final computedTitle = isAccepted
          ? kFriendRequestAcceptedTitle
          : kFriendRequestDeclinedTitle;

      final fallbackBody = friendName.isNotEmpty
          ? '${_quoteNick(friendName)} ${isAccepted ? 'принял' : 'отклонил'} запрос в друзья.'
          : 'Откройте приложение, чтобы посмотреть.';

      final computedBody = rawBody.isNotEmpty
          ? (friendName.isNotEmpty
              ? _ensureNickQuotedInText(rawBody, friendName)
              : rawBody)
          : fallbackBody;

      await _showFriendOwnerResultDialog(
        title: title.isEmpty ? computedTitle : title,
        body: computedBody,
        isAccepted: isAccepted,
      );

      // ✅ ACK/consume строго после реального UI
      await _consumeInboxDeliveryIfPossibleFromPayload(payload);
      return;
    }

    if (type == 'FRIEND_REMOVED') {
      final title = (payload['title'] ?? '').toString().trim();
      final rawBody = (payload['body'] ?? '').toString().trim();

      await _showFriendRemovedDialog(
        title: title.isEmpty ? 'Вас удалили из друзей' : title,
        body: rawBody.isEmpty ? 'Вас удалили из списка друзей.' : rawBody,
      );

      // Refresh friends list after the user acknowledged the modal.
      FriendsRefreshBus.ping();

      // ✅ ACK/consume строго после реального UI
      await _consumeInboxDeliveryIfPossibleFromPayload(payload);
      return;
    }
  }

  Future<void> _showInfoDialog(
      {required String title, required String body}) async {
    final ctx = App.navigatorKey.currentContext;
    if (ctx == null) return;

    await showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 360),
            child: Text(
              body,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.3,
                  ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFriendRequestReceivedDialog({
    required String title,
    required String body,
    required String requestId,
  }) async {
    final ctx = App.navigatorKey.currentContext;
    if (ctx == null) return;

    await showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(title),
          content: ConstrainedBox(
            constraints: _kFriendDialogConstraints,
            child: Text(
              body,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.3,
                  ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                await _declineFriendRequest(requestId);
              },
              child: const Text('Отклонить'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                await _acceptFriendRequest(requestId);
              },
              child: const Text('Принять'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFriendOwnerResultDialog({
    required String title,
    required String body,
    required bool isAccepted,
  }) async {
    final ctx = App.navigatorKey.currentContext;
    if (ctx == null) return;

    await showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        final titleStyle =
            Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  color: isAccepted ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w700,
                );

        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(title, style: titleStyle),
          content: ConstrainedBox(
            constraints: _kFriendDialogConstraints,
            child: Text(
              body,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.3,
                  ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFriendRemovedDialog({
    required String title,
    required String body,
  }) async {
    final ctx = App.navigatorKey.currentContext;
    if (ctx == null) return;

    await showDialog<void>(
      context: ctx,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        final titleStyle =
            Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  color: Colors.red,
                  fontWeight: FontWeight.w700,
                );

        return AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
          actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Text(title, style: titleStyle),
          content: ConstrainedBox(
            constraints: _kFriendDialogConstraints,
            child: Text(
              body,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    height: 1.3,
                  ),
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _acceptFriendRequest(String requestId) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    if (requestId.isEmpty) return;

    try {
      await _supabase.rpc('accept_friend_request_v2', params: {
        'p_user_id': userId,
        'p_request_id': requestId,
      });
    } catch (e) {
      await _showInfoDialog(title: 'Ошибка', body: e.toString());
      return;
    }

    // Trigger canonical friends screen refresh (invitee has no owner-result INBOX event).
    FriendsRefreshBus.ping();

    final ctx = App.navigatorKey.currentContext;
    if (ctx != null) {
      await showCenterToast(
        ctx,
        message: 'Запрос принят',
        isError: false,
      );
    }
  }

  Future<void> _declineFriendRequest(String requestId) async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    if (requestId.isEmpty) return;

    try {
      await _supabase.rpc('decline_friend_request_v2', params: {
        'p_user_id': userId,
        'p_request_id': requestId,
      });
    } catch (e) {
      await _showInfoDialog(title: 'Ошибка', body: e.toString());
      return;
    }

    // Trigger canonical friends screen refresh (invitee has no owner-result INBOX event).
    FriendsRefreshBus.ping();

    final ctx = App.navigatorKey.currentContext;
    if (ctx != null) {
      await showCenterToast(
        ctx,
        message: 'Запрос отклонён',
        isError: true,
      );
    }
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

            final deliveryId = (newRow['id'] ??
                    newRow['delivery_id'] ??
                    newRow['deliveryId'] ??
                    '')
                .toString()
                .trim();
            void consumeIfReady() {
              if (deliveryId.isEmpty) return;
              _scheduleConsumeInboxDelivery(deliveryId);
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

            // Ensure delivery id is available in payload for later ACK/consume logic.
            final _deliveryId = (newRow['id'] ?? '').toString();
            if (_deliveryId.isNotEmpty) {
              payloadMap['delivery_id'] = _deliveryId;
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
                payloadType != 'PLAN_INTERNAL_INVITE_ACCEPTED' &&
                payloadType != 'PLAN_INTERNAL_INVITE_DECLINED' &&
                payloadType != 'PLAN_MEMBER_LEFT' &&
                payloadType != 'PLAN_MEMBER_REMOVED' &&
                payloadType != 'PLAN_MEMBER_JOINED_BY_INVITE' &&
                payloadType != 'PLAN_DELETED' &&
                payloadType != 'FRIEND_REQUEST_RECEIVED' &&
                payloadType != 'FRIEND_REQUEST_ACCEPTED' &&
                payloadType != 'FRIEND_REQUEST_DECLINED' &&
                payloadType != 'FRIEND_REMOVED') {
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
              final planTitle =
                  (payloadMap['plan_title'] ?? payloadMap['planTitle'] ?? '')
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
              final cleanBody = (bodyTrim.isEmpty ||
                      bodyTrim == 'Один из участников покинул план.')
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
              consumeIfReady();
              return;
            }

// ✅ Separate layer: PLAN_MEMBER_JOINED_BY_INVITE -> in-app info modal (foreground).
            if (payloadType == 'PLAN_MEMBER_JOINED_BY_INVITE') {
              final planId = (payloadMap['plan_id'] ??
                      payloadMap['planId'] ??
                      newRow['plan_id'] ??
                      newRow['planId'] ??
                      '')
                  .toString();
              final joinedUserId = (payloadMap['joined_user_id'] ??
                      payloadMap['joinedUserId'] ??
                      payloadMap['joined_userId'] ??
                      '')
                  .toString();

              if (planId.isEmpty || joinedUserId.isEmpty) return;

              final title = (payloadMap['title'] ?? '').toString();
              final body = (payloadMap['body'] ?? '').toString();
              final joinedNickname = (payloadMap['joined_nickname'] ??
                      payloadMap['joinedNickname'] ??
                      '')
                  .toString();
              final planTitle =
                  (payloadMap['plan_title'] ?? payloadMap['planTitle'] ?? '')
                      .toString();

              if (kDebugMode) {
                debugPrint(
                  '[INBOX] plan-member-joined-by-invite insert planId=$planId joinedUserId=$joinedUserId',
                );
              }

              final cleanJoinedNickname =
                  joinedNickname.trim().isEmpty ? null : joinedNickname.trim();
              final cleanPlanTitle =
                  planTitle.trim().isEmpty ? null : planTitle.trim();
              final cleanTitle = title.trim().isEmpty ? null : title.trim();

              final bodyTrim = body.trim();
              final cleanBody = bodyTrim.isEmpty ? null : bodyTrim;

              PlanMemberJoinedByInviteUiCoordinator.instance.enqueue(
                PlanMemberJoinedByInviteUiRequest(
                  planId: planId,
                  joinedUserId: joinedUserId,
                  joinedNickname: cleanJoinedNickname,
                  planTitle: cleanPlanTitle,
                  title: cleanTitle,
                  body: cleanBody,
                  source: PlanMemberJoinedByInviteUiSource.foreground,
                ),
              );
              consumeIfReady();
              return;
            }

// ✅ Separate layer: PLAN_MEMBER_REMOVED -> in-app info modal (foreground).
            if (payloadType == 'PLAN_MEMBER_REMOVED') {
              final planId = (payloadMap['plan_id'] ??
                      payloadMap['planId'] ??
                      newRow['plan_id'] ??
                      newRow['planId'] ??
                      '')
                  .toString();
              final removedUserId = (payloadMap['removed_user_id'] ??
                      payloadMap['removedUserId'] ??
                      payloadMap['removed_userId'] ??
                      '')
                  .toString();
              final ownerUserId = (payloadMap['owner_user_id'] ??
                      payloadMap['ownerUserId'] ??
                      payloadMap['owner_userId'] ??
                      '')
                  .toString();
              if (planId.isEmpty ||
                  removedUserId.isEmpty ||
                  ownerUserId.isEmpty) return;

              final title = (payloadMap['title'] ?? '').toString();
              final body = (payloadMap['body'] ?? '').toString();
              final ownerNickname = (payloadMap['owner_nickname'] ??
                      payloadMap['ownerNickname'] ??
                      '')
                  .toString();
              final planTitle =
                  (payloadMap['plan_title'] ?? payloadMap['planTitle'] ?? '')
                      .toString();

              if (kDebugMode) {
                debugPrint(
                  '[INBOX] plan-member-removed insert planId=$planId removedUserId=$removedUserId ownerUserId=$ownerUserId',
                );
              }

              final cleanOwnerNickname =
                  ownerNickname.trim().isEmpty ? null : ownerNickname.trim();
              final cleanPlanTitle =
                  planTitle.trim().isEmpty ? null : planTitle.trim();
              final cleanTitle = title.trim().isEmpty ? null : title.trim();
              final cleanBody = body.trim().isEmpty ? null : body.trim();

              PlanMemberRemovedUiCoordinator.instance.enqueue(
                PlanMemberRemovedUiRequest(
                  planId: planId,
                  removedUserId: removedUserId,
                  ownerUserId: ownerUserId,
                  ownerNickname: cleanOwnerNickname,
                  planTitle: cleanPlanTitle,
                  title: cleanTitle,
                  body: cleanBody,
                  source: PlanMemberRemovedUiSource.foreground,
                ),
              );
              consumeIfReady();
              return;
            }

            // ✅ Separate layer: PLAN_DELETED -> in-app info modal (foreground).
            if (payloadType == 'PLAN_DELETED') {
              final planId = (payloadMap['plan_id'] ??
                      payloadMap['planId'] ??
                      newRow['plan_id'] ??
                      newRow['planId'] ??
                      '')
                  .toString()
                  .trim();

              // ✅ Server canonical key is owner_app_user_id (see payloadKeys in logs).
              // Keep fallbacks for any legacy variants.
              final ownerUserId = (payloadMap['owner_app_user_id'] ??
                      payloadMap['owner_user_id'] ??
                      payloadMap['ownerUserId'] ??
                      '')
                  .toString()
                  .trim();

              // ✅ Always log precheck so we never "silently return" again.
              if (kDebugMode) {
                debugPrint(
                  '[INBOX] plan-deleted precheck planId="$planId" ownerUserId="$ownerUserId" keys=${payloadMap.keys.toList()}',
                );
              }

              if (planId.isEmpty || ownerUserId.isEmpty) return;

              final title = (payloadMap['title'] ?? '').toString();
              final body = (payloadMap['body'] ?? '').toString();
              final ownerNickname = (payloadMap['owner_nickname'] ??
                      payloadMap['ownerNickname'] ??
                      '')
                  .toString();
              final planTitle =
                  (payloadMap['plan_title'] ?? payloadMap['planTitle'] ?? '')
                      .toString();

              if (kDebugMode) {
                debugPrint(
                  '[INBOX] plan-deleted insert planId=$planId ownerUserId=$ownerUserId',
                );
              }

              PlanDeletedUiCoordinator.instance.enqueue(
                PlanDeletedUiRequest(
                  planId: planId,
                  ownerUserId: ownerUserId,
                  ownerNickname: ownerNickname.trim().isEmpty
                      ? null
                      : ownerNickname.trim(),
                  planTitle: planTitle.trim().isEmpty ? null : planTitle.trim(),
                  title: title.trim().isEmpty ? null : title.trim(),
                  body: body.trim().isEmpty ? null : body.trim(),
                  source: PlanDeletedUiSource.foreground,
                ),
              );

              // Keep same consume pattern as other plan-events in this router.
              consumeIfReady();
              return;
            }

            if (payloadType == 'PLAN_INTERNAL_INVITE_ACCEPTED' ||
                payloadType == 'PLAN_INTERNAL_INVITE_DECLINED') {
              final inviteId =
                  (payloadMap['invite_id'] ?? payloadMap['inviteId'] ?? '')
                      .toString();
              final planId =
                  (payloadMap['plan_id'] ?? payloadMap['planId'] ?? '')
                      .toString();
              final body = (payloadMap['body'] ?? '').toString();
              final isAccept = payloadType == 'PLAN_INTERNAL_INVITE_ACCEPTED';

              InviteUiCoordinator.instance.enqueueOwnerResult(
                OwnerResultUiRequest(
                  inviteId: inviteId,
                  planId: planId,
                  action: isAccept ? 'ACCEPT' : 'DECLINE',
                  title: isAccept
                      ? 'Приглашение принято'
                      : 'Приглашение отклонено',
                  body: body,
                  source: InviteUiSource.foreground,
                ),
              );

              consumeIfReady();
              return;
            }

            if (payloadType == 'FRIEND_REQUEST_RECEIVED' ||
                payloadType == 'FRIEND_REQUEST_ACCEPTED' ||
                payloadType == 'FRIEND_REQUEST_DECLINED') {
              _enqueueFriendRequestUi(payloadMap);
              consumeIfReady();
              return;
            }

            if (payloadType == 'FRIEND_REMOVED') {
              // ✅ For FRIEND_REMOVED we must show modal first, then consume after close.
              unawaited(_handleFriendDeliveryPayload(payloadMap));
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
              consumeIfReady();
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

  Future<void> _consumeInboxDelivery({required String deliveryId}) async {
    final appUserId = _userId;
    if (appUserId == null || appUserId.trim().isEmpty) return;
    final id = deliveryId.trim();
    if (id.isEmpty) return;

    try {
      await _supabase.rpc(
        'consume_notification_delivery_v1',
        params: <String, dynamic>{
          'p_app_user_id': appUserId,
          'p_delivery_id': id,
        },
      );
      if (kDebugMode) {
        debugPrint('[INBOX] consumed delivery id=$id');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[INBOX] consume failed delivery id=$id error=$e');
      }
    }
  }

  void _scheduleConsumeInboxDelivery(String deliveryId) {
    final id = deliveryId.trim();
    if (id.isEmpty) return;

    // Only consume when UI shell is ready to avoid losing UX.
    if (_appShellReady && _userId != null && _userId!.trim().isNotEmpty) {
      unawaited(_consumeInboxDelivery(deliveryId: id));
      return;
    }

    _pendingConsumeDeliveryIds.add(id);
  }

  void _flushPendingConsumeInboxDeliveriesIfAny() {
    if (!_appShellReady) return;
    if (_pendingConsumeDeliveryIds.isEmpty) return;

    final items = List<String>.from(_pendingConsumeDeliveryIds);
    _pendingConsumeDeliveryIds.clear();
    for (final id in items) {
      unawaited(_consumeInboxDelivery(deliveryId: id));
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
        PlansScreen(
          appUserId: userId,
          onAddFriend: (
              {required targetPublicId, required targetAppUserId}) async {
            // Reuse existing Friends flow (server-first).
            // targetAppUserId is available for future needs; current RPC uses public_id.
            final friendsRepo = FriendsRepositoryImpl(Supabase.instance.client);
            await friendsRepo.requestFriendByPublicId(
              appUserId: userId,
              targetPublicId: targetPublicId,
            );
          },
        ),
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
          nav3.pushReplacement(
            noAnimRoute(
              PlansScreen(
                appUserId: userId,
                onAddFriend: (
                    {required targetPublicId, required targetAppUserId}) async {
                  // Reuse existing Friends flow (server-first).
                  // targetAppUserId is available for future needs; current RPC uses public_id.
                  final friendsRepo =
                      FriendsRepositoryImpl(Supabase.instance.client);
                  await friendsRepo.requestFriendByPublicId(
                    appUserId: userId,
                    targetPublicId: targetPublicId,
                  );
                },
              ),
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
      unawaited(showCenterToast(context,
          message: 'Ошибка инвайта: $e', isError: true));
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
    _flushPendingConsumeInboxDeliveriesIfAny();
    _flushPendingFriendRequestsIfAny();
    _flushPendingFriendOpenIntentsIfAny();
    PlanMemberLeftUiCoordinator.instance.setRootUiReady(true);

    PlanMemberRemovedUiCoordinator.instance.setRootUiReady(true);
    PlanDeletedUiCoordinator.instance.setRootUiReady(true);
    PlanMemberJoinedByInviteUiCoordinator.instance.setRootUiReady(true);
    _flushPendingFriendRequestsIfAny();
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
