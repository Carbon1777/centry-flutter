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
  static const String kInviteDialogDefaultBody =
      'Вас пригласили в план. Принять приглашение?';
  static const String kInviteAcceptedToast = 'Приглашение принято';
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

  bool _restoring = true;
  bool _inviteDialogVisible = false;

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

  // ✅ Pending internal invite dialog (open-only push -> in-app modal)
  String? _pendingDialogInviteId;
  String? _pendingDialogPlanId;
  String? _pendingDialogActionToken;
  String? _pendingDialogTitle;
  String? _pendingDialogBody;
  Timer? _pendingInviteDialogTimer;

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
        final actionId =
            (extras['actionId'] ?? extras['action_id'] ?? '').toString().trim().toUpperCase();

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
            final shouldRouteViaCoordinator = !mounted || (_appShellReady && !_restoring);

            if (kDebugMode) {
              debugPrint(
                '[IntentBridge] invite OPEN inviteId=$inviteId planId=$planId '
                'mounted=$mounted restoring=$_restoring appShell=$_appShellReady '
                'viaCoordinator=$shouldRouteViaCoordinator',
              );
            }

            if (shouldRouteViaCoordinator) {
              InviteUiCoordinator.instance.enqueue(
                InviteUiRequest(
                  inviteId: inviteId,
                  planId: planId,
                  title: title,
                  body: body,
                  source: InviteUiSource.backgroundIntent,
                ),
              );
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

        // ✅ New canon: system push only opens app. Product actions happen in in-app modal.
        if (normalized == 'OPEN') {
          _queuePendingInviteDialog(
            inviteId: inviteId,
            planId: planId,
            actionToken: actionToken,
            title: title,
            body: body,
          );
          return;
        }

        // Ignore legacy/unknown actions from old notifications.
        if (kDebugMode) {
          debugPrint('[InviteModal] ignore local notif action=$normalized');
        }
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

      // In-app modal is canonical. Queue it and show only after welcome/home phase.
      _queueInternalInviteDialogFromRemoteMessage(m);
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

    _queuePendingInviteDialog(
      inviteId: inviteId,
      planId: planId,
      actionToken: actionToken.isEmpty ? null : actionToken,
      title: title,
      body: body,
    );
  }

  void _ensureInboxInvitesRealtimeSubscribed() {
    // Canonical C (foreground): consume server-fact INBOX deliveries via Realtime.
    // A/B are preserved (they already work via push-tap + intent bridge / pending dialog).
    if (!mounted) return;
    if (_restoring) return;
    if (!_appShellReady) return;

    final userId = _userId;
    if (userId == null || userId.isEmpty) return;

    // Already subscribed for this user.
    if (_inboxInvitesChannel != null && _inboxInvitesChannelUserId == userId) {
      return;
    }

    // User switched or channel not ready yet.
    _disposeInboxInvitesRealtimeSubscription();
    _inboxInvitesChannelUserId = userId;

    if (kDebugMode) {
      debugPrint('[INBOX] subscribe notification_deliveries (userId=$userId)');
    }

    final channel = _supabase.channel('inbox_invites_$userId');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notification_deliveries',
      callback: (payload) {
        try {
          final newRow = payload.newRecord;
          if (newRow.isEmpty) return;

          // RLS should already scope rows to this user.
          final deliveryChannel = (newRow['channel'] ?? '').toString();
          final status = (newRow['status'] ?? '').toString();

          // We only care about INBOX pending deliveries.
          if (deliveryChannel != 'INBOX') return;
          if (status.isNotEmpty && status != 'PENDING') return;

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

          // Canonical: we only show modal for actual invites, not for "invite response" messages.
          // Invite payload has: type=PLAN_INTERNAL_INVITE and actions=[ACCEPT,DECLINE]
          final payloadType = (payloadMap['type'] ?? '').toString();
          if (payloadType.isNotEmpty && payloadType != 'PLAN_INTERNAL_INVITE') return;

          final actionsRaw = payloadMap['actions'];
          final isInviteWithActions = actionsRaw is List && actionsRaw.isNotEmpty;
          if (!isInviteWithActions) return;

          // Some rows represent "Ответ на приглашение" and contain `action` instead of `actions`.
          // Those are informational and must NOT open the accept/decline modal.
          if (payloadMap.containsKey('action')) return;

          final inviteId = (payloadMap['invite_id'] ??
                  payloadMap['inviteId'] ??
                  newRow['invite_id'] ??
                  '')
              .toString();
          final planId =
              (payloadMap['plan_id'] ?? payloadMap['planId'] ?? newRow['plan_id'] ?? '')
                  .toString();
          final actionToken =
              (payloadMap['action_token'] ?? payloadMap['actionToken'] ?? '').toString();
          final title = (payloadMap['title'] ?? '').toString();
          final body = (payloadMap['body'] ?? '').toString();

          if (inviteId.isEmpty || planId.isEmpty) return;

          if (kDebugMode) {
            debugPrint(
              '[INBOX] delivery insert inviteId=$inviteId planId=$planId status=$status payloadType=$payloadType',
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
      if (kDebugMode) {
        debugPrint('[INBOX] realtime status=$status error=$error');
      }
    });

  }

  Future<void> _disposeInboxInvitesRealtimeSubscription() async {
    final ch = _inboxInvitesChannel;
    _inboxInvitesChannel = null;
    _inboxInvitesChannelUserId = null;
    if (ch == null) return;

    try {
      await _supabase.removeChannel(ch);
    } catch (_) {
      // ignore dispose errors
    }
  }


  void _queuePendingInviteDialog({
    required String inviteId,
    required String planId,
    String? actionToken,
    String? title,
    String? body,
  }) {
    _pendingDialogInviteId = inviteId;
    _pendingDialogPlanId = planId;
    _pendingDialogActionToken = actionToken;
    _pendingDialogTitle = (title == null || title.trim().isEmpty)
        ? kInviteDialogDefaultTitle
        : title;
    _pendingDialogBody = body ?? '';

    _schedulePendingInviteDialogIfReady();
  }

  void _schedulePendingInviteDialogIfReady() {
    if (!mounted) return;
    if (_restoring) return;
    if (!_appShellReady) return;
    if (_inviteDialogVisible) return;
    if (_pendingDialogInviteId == null || _pendingDialogPlanId == null) return;

    _pendingInviteDialogTimer?.cancel();
    unawaited(_showPendingInviteDialogNow());
  }

  Future<void> _showPendingInviteDialogNow() async {
    if (!mounted) return;
    if (_inviteDialogVisible) return;

    final inviteId = _pendingDialogInviteId;
    final planId = _pendingDialogPlanId;
    final actionToken = _pendingDialogActionToken;
    final title = _pendingDialogTitle ?? kInviteDialogDefaultTitle;
    final body = _pendingDialogBody ?? '';

    if (inviteId == null ||
        inviteId.isEmpty ||
        planId == null ||
        planId.isEmpty) {
      return;
    }

    _inviteDialogVisible = true;

    await Future<void>.delayed(Duration.zero);

    if (!mounted) {
      _inviteDialogVisible = false;
      return;
    }

    String? dialogAction;

    try {
      dialogAction = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: Text(title),
            content: Text(
              body.isEmpty ? kInviteDialogDefaultBody : body,
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop('DECLINE');
                },
                child: const Text('Отклонить'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop('ACCEPT');
                },
                child: const Text('Принять'),
              ),
            ],
          );
        },
      );
    } finally {
      _inviteDialogVisible = false;
    }

    if (dialogAction != 'ACCEPT' && dialogAction != 'DECLINE') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _schedulePendingInviteDialogIfReady();
      });
      return;
    }

    _pendingDialogInviteId = null;
    _pendingDialogPlanId = null;
    _pendingDialogActionToken = null;
    _pendingDialogTitle = null;
    _pendingDialogBody = null;

    final resolvedAction = dialogAction!;

    await _handleInternalInviteAction(
      inviteId: inviteId,
      action: resolvedAction,
      planId: planId,
      actionToken: actionToken,
    );
  }

  Future<void> _handleInternalInviteAction({
    required String inviteId,
    required String planId,
    required String action,
    String? actionToken,
  }) async {
    if (_processingInviteAction) {
      if (kDebugMode) {
        debugPrint('[InviteAction] ignored: already processing inviteId=$inviteId action=$action');
      }
      return;
    }

    final userId = _userId;
    if (userId == null || userId.isEmpty) {
      if (kDebugMode) {
        debugPrint('[InviteAction] ignored: userId missing inviteId=$inviteId action=$action');
      }
      return;
    }

    _processingInviteAction = true;
    try {
      if (kDebugMode) {
        debugPrint('[InviteAction] rpc start inviteId=$inviteId action=$action planId=$planId userId=$userId');
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
        debugPrint('[InviteAction] rpc success inviteId=$inviteId action=$action planId=$planId mounted=$mounted appShell=$_appShellReady');
      }

      if (action == 'ACCEPT') {
        if (kDebugMode) {
          debugPrint('[InviteAction] queue open details inviteId=$inviteId planId=$planId');
        }
        _queuePendingPlanOpen(
          planId,
          toastMessage: kInviteAcceptedToast,
        );
      } else if (action == 'DECLINE') {
        final toastCtx = App.navigatorKey.currentContext ?? (mounted ? context : null);
        if (toastCtx != null) {
          unawaited(showCenterToast(toastCtx, message: kInviteDeclinedToast));
        }
      }
    } on PostgrestException catch (e) {
      if (kDebugMode) {
        debugPrint('[InviteAction] PostgrestException inviteId=$inviteId action=$action message=${e.message}');
      }
      final toastCtx = App.navigatorKey.currentContext ?? (mounted ? context : null);
      if (toastCtx != null) {
        unawaited(showCenterToast(toastCtx, message: e.message, isError: true));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[InviteAction] error inviteId=$inviteId action=$action error=$e');
      }
      final toastCtx = App.navigatorKey.currentContext ?? (mounted ? context : null);
      if (toastCtx != null) {
        unawaited(showCenterToast(toastCtx, message: 'Ошибка: $e', isError: true));
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
      debugPrint('[InviteNav] open details requested planId=$planId userId=$userId');
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

      unawaited(
        nav2.push(
          MaterialPageRoute(
            builder: (_) => PlanDetailsScreen(
              appUserId: userId,
              planId: planId,
              repository: repo,
            ),
          ),
        ),
      );

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
      debugPrint('[InviteNav] queue plan open planId=$planId toast=$toastMessage');
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
      _schedulePendingInviteDialogIfReady();
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
      _schedulePendingInviteDialogIfReady();
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
          unawaited(_disposeInboxInvitesRealtimeSubscription());
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
        unawaited(_disposeInboxInvitesRealtimeSubscription());
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

      _runPostIdentityFlows();
      return;
    }

    // ===== ONBOARDING =====
    if (!mounted) return;
    unawaited(_disposeInboxInvitesRealtimeSubscription());
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

    _runPostIdentityFlows();
  }

  void _onAppShellReady() {
    if (_appShellReady) return;
    _appShellReady = true;
    InviteUiCoordinator.instance.setRootUiReady(true);

    _ensureInboxInvitesRealtimeSubscribed();

    _homeVisibleAt ??= DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _schedulePendingPlanOpenIfReady();
      _schedulePendingInviteDialogIfReady();
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
    _pendingInviteDialogTimer?.cancel();
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