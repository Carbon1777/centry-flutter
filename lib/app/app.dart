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
import '../data/legal/legal_repository_impl.dart';
import '../features/home/home_screen.dart';
import '../ui/activity_feed/activity_feed_screen.dart';
import '../features/legal/legal_agreement_screen.dart';
import '../features/onboarding/intro_video_screen.dart';
import '../features/onboarding/nickname_screen.dart';
import '../push/push_notifications.dart';
import '../ui/common/center_toast.dart';
import '../ui/private_chats/private_chats_list_screen.dart';
import '../ui/attention_signs/attention_sign_box_screen.dart';
import '../ui/attention_signs/attention_signs_bus.dart';
import '../ui/common/modal_events_checker.dart';

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
      scrollBehavior: const MaterialScrollBehavior().copyWith(overscroll: false),

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

  // Pending push OPEN intents for invites/plan events until identity + shell are ready.
  final List<Map<String, dynamic>> _pendingNotificationOpenIntents =
      <Map<String, dynamic>>[];
  String? _lastHandledNotificationOpenKey;
  DateTime? _lastHandledNotificationOpenAt;
  // Pending consume requests when delivery arrives before shell is ready.
  final List<String> _pendingConsumeDeliveryIds = <String>[];
  DateTime? _homeVisibleAt;
  Timer? _pendingPlanOpenTimer;
  bool _appShellReady = false;
  int _shellGeneration = 0;

  // Post-identity pipeline guards (avoid reentry/loops).
  bool _postIdentityFlowsRunning = false;
  bool _postIdentityFlowsRerunRequested = false;

  // Legal acceptance check for returning users.
  bool _legalNeedsAcceptance = false;
  bool _legalCheckInProgress = false;

  // Intro video (показывается один раз при первом запуске).
  bool _showIntroVideo = false;

  // Welcome animation completed — переключает build() с HomeScreen на ActivityFeedScreen.
  // НЕ сбрасывается при token refresh (_restore с тем же userId).
  bool _welcomeCompleted = false;

  // ✅ Push token registration guards (UI-only, no business logic)
  bool _registeringDeviceToken = false;
  bool _registerDeviceTokenRetryRequested = false;
  String? _lastRegisteredDeviceTokenKey;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);



    unawaited(_refreshGeoAndSync());

    _initAuthListener();
    _initDeepLinks();
    _initAndroidNotificationIntentBridge();

    // ✅ local notifications init (actions)
    unawaited(_initLocalNotifications());

    // ✅ Setup FCM listeners (mobile only)
    _initFcmTokenRefresh();
    _initFcmForegroundMessages();
    _initFcmMessageOpenHandlers();

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

        if (intentData.isNotEmpty) {
          final uri = Uri.tryParse(intentData);
          if (uri != null) {
            await _handleIncomingUri(uri);
          }
        }

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

        final effectiveType = (payload['type'] ??
                payload['kind'] ??
                extras['type'] ??
                extras['kind'] ??
                '')
            .toString()
            .trim();
        final planId = (payload['plan_id'] ??
                payload['planId'] ??
                extras['plan_id'] ??
                extras['planId'] ??
                '')
            .toString()
            .trim();
        final inviteId = (payload['invite_id'] ??
                payload['inviteId'] ??
                extras['invite_id'] ??
                extras['inviteId'] ??
                '')
            .toString()
            .trim();
        final title =
            (payload['title'] ?? extras['title'] ?? '').toString().trim();
        final body =
            (payload['body'] ?? extras['body'] ?? '').toString().trim();

        if (actionId == 'OPEN') {
          if (inviteId.isNotEmpty && planId.isNotEmpty) {
            await _handleInviteOpenFromNotificationTap(
              inviteId: inviteId,
              planId: planId,
              actionToken: (payload['action_token'] ??
                      payload['actionToken'] ??
                      extras['action_token'] ??
                      extras['actionToken'] ??
                      '')
                  .toString()
                  .trim(),
              kindHint:
                  (payload['kind'] ?? extras['kind'] ?? '').toString().trim(),
              actionHint: (payload['action'] ?? extras['action'] ?? '')
                  .toString()
                  .trim(),
              title: title,
              body: body,
              openSource: 'intent_bridge',
            );
            return;
          }

          const scheduledTypes = <String>{
            'PLAN_VOTING_REMINDER_DATE',
            'PLAN_VOTING_REMINDER_PLACE',
            'PLAN_VOTING_REMINDER_BOTH',
            'PLAN_OWNER_PRIORITY_DATE',
            'PLAN_OWNER_PRIORITY_PLACE',
            'PLAN_OWNER_PRIORITY_BOTH',
            'PLAN_EVENT_REMINDER_24H',
          };

          if (scheduledTypes.contains(effectiveType)) {
            if (planId.isNotEmpty) {
              await _handlePlanScheduledNotificationOpenFromNotificationTap(
                type: effectiveType,
                planId: planId,
                eventId: (payload['event_id'] ??
                        payload['eventId'] ??
                        extras['event_id'] ??
                        extras['eventId'] ??
                        '')
                    .toString()
                    .trim(),
                planTitle: (payload['plan_title'] ??
                        payload['planTitle'] ??
                        extras['plan_title'] ??
                        extras['planTitle'] ??
                        '')
                    .toString()
                    .trim(),
                eventAt: (payload['event_at'] ??
                        payload['eventAt'] ??
                        extras['event_at'] ??
                        extras['eventAt'] ??
                        '')
                    .toString()
                    .trim(),
                eventDatetimeLabel: (payload['event_datetime_label'] ??
                        payload['eventDatetimeLabel'] ??
                        extras['event_datetime_label'] ??
                        extras['eventDatetimeLabel'] ??
                        '')
                    .toString()
                    .trim(),
                placeTitle: (payload['place_title'] ??
                        payload['placeTitle'] ??
                        extras['place_title'] ??
                        extras['placeTitle'] ??
                        '')
                    .toString()
                    .trim(),
                title: title,
                body: body,
                openSource: 'intent_bridge',
              );
              return;
            }
          }

          if (effectiveType == 'PLAN_MEMBER_LEFT') {
            final leftUserId = (payload['left_user_id'] ??
                    payload['leftUserId'] ??
                    payload['member_user_id'] ??
                    payload['memberUserId'] ??
                    extras['left_user_id'] ??
                    extras['leftUserId'] ??
                    extras['member_user_id'] ??
                    extras['memberUserId'] ??
                    '')
                .toString()
                .trim();
            if (planId.isNotEmpty && leftUserId.isNotEmpty) {
              await _handlePlanMemberLeftOpenFromNotificationTap(
                planId: planId,
                leftUserId: leftUserId,
                leftNickname: (payload['left_nickname'] ??
                        payload['leftNickname'] ??
                        payload['member_nickname'] ??
                        payload['memberNickname'] ??
                        extras['left_nickname'] ??
                        extras['leftNickname'] ??
                        extras['member_nickname'] ??
                        extras['memberNickname'] ??
                        '')
                    .toString()
                    .trim(),
                planTitle: (payload['plan_title'] ??
                        payload['planTitle'] ??
                        extras['plan_title'] ??
                        extras['planTitle'] ??
                        '')
                    .toString()
                    .trim(),
                eventId: (payload['event_id'] ??
                        payload['eventId'] ??
                        extras['event_id'] ??
                        extras['eventId'] ??
                        '')
                    .toString()
                    .trim(),
                title: title,
                body: body,
                openSource: 'intent_bridge',
              );
              return;
            }
          }

          if (effectiveType == 'PLAN_MEMBER_REMOVED') {
            final removedUserId = (payload['removed_user_id'] ??
                    payload['removedUserId'] ??
                    extras['removed_user_id'] ??
                    extras['removedUserId'] ??
                    '')
                .toString()
                .trim();
            final ownerUserId = (payload['owner_user_id'] ??
                    payload['ownerUserId'] ??
                    extras['owner_user_id'] ??
                    extras['ownerUserId'] ??
                    '')
                .toString()
                .trim();
            if (planId.isNotEmpty &&
                removedUserId.isNotEmpty &&
                ownerUserId.isNotEmpty) {
              await _handlePlanMemberRemovedOpenFromNotificationTap(
                planId: planId,
                removedUserId: removedUserId,
                ownerUserId: ownerUserId,
                ownerNickname: (payload['owner_nickname'] ??
                        payload['ownerNickname'] ??
                        extras['owner_nickname'] ??
                        extras['ownerNickname'] ??
                        '')
                    .toString()
                    .trim(),
                planTitle: (payload['plan_title'] ??
                        payload['planTitle'] ??
                        extras['plan_title'] ??
                        extras['planTitle'] ??
                        '')
                    .toString()
                    .trim(),
                eventId: (payload['event_id'] ??
                        payload['eventId'] ??
                        extras['event_id'] ??
                        extras['eventId'] ??
                        '')
                    .toString()
                    .trim(),
                title: title,
                body: body,
                openSource: 'intent_bridge',
              );
              return;
            }
          }

          if (effectiveType == 'PLAN_MEMBER_JOINED_BY_INVITE') {
            final joinedUserId = (payload['joined_user_id'] ??
                    payload['joinedUserId'] ??
                    extras['joined_user_id'] ??
                    extras['joinedUserId'] ??
                    '')
                .toString()
                .trim();
            if (planId.isNotEmpty && joinedUserId.isNotEmpty) {
              await _handlePlanMemberJoinedByInviteOpenFromNotificationTap(
                planId: planId,
                joinedUserId: joinedUserId,
                joinedNickname: (payload['joined_nickname'] ??
                        payload['joinedNickname'] ??
                        extras['joined_nickname'] ??
                        extras['joinedNickname'] ??
                        '')
                    .toString()
                    .trim(),
                planTitle: (payload['plan_title'] ??
                        payload['planTitle'] ??
                        extras['plan_title'] ??
                        extras['planTitle'] ??
                        '')
                    .toString()
                    .trim(),
                eventId: (payload['event_id'] ??
                        payload['eventId'] ??
                        extras['event_id'] ??
                        extras['eventId'] ??
                        '')
                    .toString()
                    .trim(),
                title: title,
                body: body,
                openSource: 'intent_bridge',
              );
              return;
            }
          }

          if (effectiveType == 'PLAN_DELETED') {
            final ownerUserId = (payload['owner_app_user_id'] ??
                    payload['owner_user_id'] ??
                    payload['ownerUserId'] ??
                    extras['owner_app_user_id'] ??
                    extras['owner_user_id'] ??
                    extras['ownerUserId'] ??
                    '')
                .toString()
                .trim();
            if (planId.isNotEmpty && ownerUserId.isNotEmpty) {
              await _handlePlanDeletedOpenFromNotificationTap(
                planId: planId,
                ownerUserId: ownerUserId,
                ownerNickname: (payload['owner_nickname'] ??
                        payload['ownerNickname'] ??
                        extras['owner_nickname'] ??
                        extras['ownerNickname'] ??
                        '')
                    .toString()
                    .trim(),
                planTitle: (payload['plan_title'] ??
                        payload['planTitle'] ??
                        extras['plan_title'] ??
                        extras['planTitle'] ??
                        '')
                    .toString()
                    .trim(),
                eventId: (payload['event_id'] ??
                        payload['eventId'] ??
                        extras['event_id'] ??
                        extras['eventId'] ??
                        '')
                    .toString()
                    .trim(),
                title: title,
                body: body,
                openSource: 'intent_bridge',
              );
              return;
            }
          }

          if (effectiveType == 'ATTENTION_SIGN_RECEIVED') {
            await _handleAttentionSignOpen();
            return;
          }

          if (effectiveType.startsWith('FRIEND_')) {
            _triggerCheckAndShowModalEvents();
            return;
          }

          if (effectiveType == 'PRIVATE_CHAT_MESSAGE') {
            await _handlePrivateChatMessageOpen();
            return;
          }

          if (effectiveType == 'ATTENTION_SIGN_ACCEPTED' ||
              effectiveType == 'ATTENTION_SIGN_DECLINED') {
            _triggerCheckAndShowModalEvents();
            return;
          }

          if (effectiveType == 'PLAN_CHAT_MESSAGE') {
            return;
          }
        }
      } catch (e) {
        // ignore handler errors
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

        if (normalized == 'OPEN') {
          await _handleInviteOpenFromNotificationTap(
            inviteId: inviteId,
            planId: planId,
            actionToken: (actionToken ?? '').trim(),
            title: (title ?? '').trim(),
            body: (body ?? '').trim(),
            openSource: 'local_notification',
          );
          return;
        }

      },
      onFriendOpen: ({
        required String type,
        String? eventId,
        String? requestId,
        String? title,
        String? body,
      }) async {
        _triggerCheckAndShowModalEvents();
      },
      onPlanMemberLeftOpen: ({
        required String planId,
        required String leftUserId,
        String? leftNickname,
        String? planTitle,
        String? eventId,
        String? title,
        String? body,
      }) async {
        await _handlePlanMemberLeftOpenFromNotificationTap(
          planId: planId,
          leftUserId: leftUserId,
          leftNickname: (leftNickname ?? '').trim(),
          planTitle: (planTitle ?? '').trim(),
          eventId: (eventId ?? '').trim(),
          title: (title ?? '').trim(),
          body: (body ?? '').trim(),
          openSource: 'local_notification',
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
        await _handlePlanMemberJoinedByInviteOpenFromNotificationTap(
          planId: planId,
          joinedUserId: joinedUserId,
          joinedNickname: (joinedNickname ?? '').trim(),
          planTitle: (planTitle ?? '').trim(),
          title: (title ?? '').trim(),
          body: (body ?? '').trim(),
          openSource: 'local_notification',
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
        await _handlePlanMemberRemovedOpenFromNotificationTap(
          planId: planId,
          removedUserId: removedUserId,
          ownerUserId: ownerUserId,
          ownerNickname: (ownerNickname ?? '').trim(),
          planTitle: (planTitle ?? '').trim(),
          title: (title ?? '').trim(),
          body: (body ?? '').trim(),
          openSource: 'local_notification',
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
        await _handlePlanDeletedOpenFromNotificationTap(
          planId: planId,
          ownerUserId: ownerUserId,
          ownerNickname: (ownerNickname ?? '').trim(),
          planTitle: (planTitle ?? '').trim(),
          eventId: (eventId ?? '').trim(),
          title: (title ?? '').trim(),
          body: (body ?? '').trim(),
          openSource: 'local_notification',
        );
      },
      onPlanScheduledNotificationOpen: ({
        required String type,
        required String planId,
        String? eventId,
        String? planTitle,
        String? eventAt,
        String? eventDatetimeLabel,
        String? placeTitle,
        String? title,
        String? body,
      }) async {
        await _handlePlanScheduledNotificationOpenFromNotificationTap(
          type: type,
          planId: planId,
          eventId: (eventId ?? '').trim(),
          planTitle: (planTitle ?? '').trim(),
          eventAt: (eventAt ?? '').trim(),
          eventDatetimeLabel: (eventDatetimeLabel ?? '').trim(),
          placeTitle: (placeTitle ?? '').trim(),
          title: (title ?? '').trim(),
          body: (body ?? '').trim(),
          openSource: 'local_notification',
        );
      },
      onPrivateChatMessageOpen: () async {
        await _handlePrivateChatMessageOpen();
      },
      onAttentionSignOpen: () async {
        await _handleAttentionSignOpen();
      },
    );
  }

  Future<void> _handlePrivateChatMessageOpen() async {
    final userId = (_userId ?? '').trim();
    if (userId.isEmpty) return;
    final nav = App.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateChatsListScreen(appUserId: userId),
      ),
    );
  }

  Future<void> _handleAttentionSignOpen() async {
    final userId = (_userId ?? '').trim();
    if (userId.isEmpty) return;
    final nav = App.navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => AttentionSignBoxScreen(appUserId: userId),
      ),
    );
  }

  void _initFcmForegroundMessages() {
    if (kIsWeb) return;

    _fcmMessageSub?.cancel();

    _fcmMessageSub = FirebaseMessaging.onMessage.listen((m) async {
      final msgType = (m.data['type'] ?? '').toString().trim();
      debugPrint('[FCM-FG] received type=$msgType');

      // Existing working flows: keep unchanged.
      await PushNotifications.showInternalInvite(m);
      await PushNotifications.showFriendRequest(m);

      // Chat messages (plan + private): при открытом приложении
      // push НЕ показываем — сигнализируем только красной точкой на иконках
      // (обновляется через polling в _BottomNavigationBar).

      // Знак внимания: приложение открыто — пуш не показываем,
      // только зажигаем красный кружок на Коробке и кнопке профиля.
      if (msgType == 'ATTENTION_SIGN_RECEIVED') {
        AttentionSignsBus.instance.setHasIncoming(true);
      }

      // ✅ Fallback: если Realtime INBOX ещё не доставил событие, FCM push
      // сработает как backup-триггер для показа модалок из серверной очереди.
      // Для chat-сообщений и знаков внимания модалки не нужны.
      const chatTypes = {'PLAN_CHAT_MESSAGE', 'PRIVATE_CHAT_MESSAGE'};
      if (msgType.isNotEmpty &&
          !chatTypes.contains(msgType) &&
          msgType != 'ATTENTION_SIGN_RECEIVED') {
        _triggerCheckAndShowModalEvents();
      }
    });
  }

  void _initFcmMessageOpenHandlers() {
    if (kIsWeb) return;

    // Tap on system FCM notification while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      _handleFcmMessageOpen(m.data);
    });

    // Tap on system FCM notification that launched the app from terminated state.
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _handleFcmMessageOpen(m.data);
    });
  }

  void _handleFcmMessageOpen(Map<String, dynamic> data) {
    final type = (data['type'] ?? data['kind'] ?? '').toString().trim();
    if (type.isEmpty) return;

    if (type == 'ATTENTION_SIGN_RECEIVED') {
      if (_canResolveNotificationOpenFromInbox()) {
        unawaited(_handleAttentionSignOpen());
      } else {
        _enqueueNotificationOpenIntent(<String, dynamic>{
          ...data,
          'type': type,
        });
      }
      return;
    }

    // Other types: route through the pending intent system.
    if (_canResolveNotificationOpenFromInbox()) {
      unawaited(_handlePendingNotificationOpenIntent(
          Map<String, dynamic>.from(data)));
    } else {
      _enqueueNotificationOpenIntent(Map<String, dynamic>.from(data));
    }
  }

  bool _canResolveNotificationOpenFromInbox() {
    return !_restoring && _appShellReady && (_userId ?? '').trim().isNotEmpty;
  }

  void _enqueueNotificationOpenIntent(Map<String, dynamic> intent) {
    _pendingNotificationOpenIntents.add(intent);
  }

  void _flushPendingNotificationOpenIntentsIfAny() {
    if (!_appShellReady) return;
    if ((_userId ?? '').trim().isEmpty) return;
    if (_pendingNotificationOpenIntents.isEmpty) return;

    final intents =
        List<Map<String, dynamic>>.from(_pendingNotificationOpenIntents);
    _pendingNotificationOpenIntents.clear();
    for (final intent in intents) {
      unawaited(_handlePendingNotificationOpenIntent(intent));
    }
  }

  Future<void> _handlePendingNotificationOpenIntent(
      Map<String, dynamic> intent) async {
    final type = (intent['type'] ?? '').toString().trim();
    if (type == 'PLAN_INTERNAL_INVITE') {
      final inviteId = (intent['invite_id'] ?? '').toString().trim();
      final planId = (intent['plan_id'] ?? '').toString().trim();
      if (inviteId.isEmpty || planId.isEmpty) return;
      await _handleInviteOpenFromNotificationTap(
        inviteId: inviteId,
        planId: planId,
        actionToken: (intent['action_token'] ?? '').toString().trim(),
        kindHint: (intent['kind_hint'] ?? '').toString().trim(),
        actionHint: (intent['action_hint'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
      return;
    }

    if (type == 'PLAN_MEMBER_LEFT') {
      final planId = (intent['plan_id'] ?? '').toString().trim();
      final leftUserId = (intent['left_user_id'] ?? '').toString().trim();
      if (planId.isEmpty || leftUserId.isEmpty) return;
      await _handlePlanMemberLeftOpenFromNotificationTap(
        planId: planId,
        leftUserId: leftUserId,
        leftNickname: (intent['left_nickname'] ?? '').toString().trim(),
        planTitle: (intent['plan_title'] ?? '').toString().trim(),
        eventId: (intent['event_id'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
      return;
    }

    if (type == 'PLAN_MEMBER_REMOVED') {
      final planId = (intent['plan_id'] ?? '').toString().trim();
      final removedUserId = (intent['removed_user_id'] ?? '').toString().trim();
      final ownerUserId = (intent['owner_user_id'] ?? '').toString().trim();
      if (planId.isEmpty || removedUserId.isEmpty || ownerUserId.isEmpty) {
        return;
      }
      await _handlePlanMemberRemovedOpenFromNotificationTap(
        planId: planId,
        removedUserId: removedUserId,
        ownerUserId: ownerUserId,
        ownerNickname: (intent['owner_nickname'] ?? '').toString().trim(),
        planTitle: (intent['plan_title'] ?? '').toString().trim(),
        eventId: (intent['event_id'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
      return;
    }

    if (type == 'PLAN_MEMBER_JOINED_BY_INVITE') {
      final planId = (intent['plan_id'] ?? '').toString().trim();
      final joinedUserId = (intent['joined_user_id'] ?? '').toString().trim();
      if (planId.isEmpty || joinedUserId.isEmpty) return;
      await _handlePlanMemberJoinedByInviteOpenFromNotificationTap(
        planId: planId,
        joinedUserId: joinedUserId,
        joinedNickname: (intent['joined_nickname'] ?? '').toString().trim(),
        planTitle: (intent['plan_title'] ?? '').toString().trim(),
        eventId: (intent['event_id'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
      return;
    }

    const scheduledTypes = <String>{
      'PLAN_VOTING_REMINDER_DATE',
      'PLAN_VOTING_REMINDER_PLACE',
      'PLAN_VOTING_REMINDER_BOTH',
      'PLAN_OWNER_PRIORITY_DATE',
      'PLAN_OWNER_PRIORITY_PLACE',
      'PLAN_OWNER_PRIORITY_BOTH',
      'PLAN_EVENT_REMINDER_24H',
    };

    if (scheduledTypes.contains(type)) {
      final planId = (intent['plan_id'] ?? '').toString().trim();
      if (planId.isEmpty) return;
      await _handlePlanScheduledNotificationOpenFromNotificationTap(
        type: type,
        planId: planId,
        eventId: (intent['event_id'] ?? '').toString().trim(),
        planTitle: (intent['plan_title'] ?? '').toString().trim(),
        eventAt: (intent['event_at'] ?? '').toString().trim(),
        eventDatetimeLabel:
            (intent['event_datetime_label'] ?? '').toString().trim(),
        placeTitle: (intent['place_title'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
      return;
    }

    if (type == 'PRIVATE_CHAT_MESSAGE') {
      await _handlePrivateChatMessageOpen();
      return;
    }

    if (type == 'ATTENTION_SIGN_RECEIVED') {
      await _handleAttentionSignOpen();
      return;
    }

    if (type.startsWith('FRIEND_')) {
      _triggerCheckAndShowModalEvents();
      return;
    }

    if (type == 'ATTENTION_SIGN_ACCEPTED' ||
        type == 'ATTENTION_SIGN_DECLINED') {
      _triggerCheckAndShowModalEvents();
      return;
    }

    if (type == 'PLAN_CHAT_MESSAGE') {
      return;
    }

    if (type == 'PLAN_DELETED') {
      final planId = (intent['plan_id'] ?? '').toString().trim();
      final ownerUserId = (intent['owner_user_id'] ?? '').toString().trim();
      if (planId.isEmpty || ownerUserId.isEmpty) return;
      await _handlePlanDeletedOpenFromNotificationTap(
        planId: planId,
        ownerUserId: ownerUserId,
        ownerNickname: (intent['owner_nickname'] ?? '').toString().trim(),
        planTitle: (intent['plan_title'] ?? '').toString().trim(),
        eventId: (intent['event_id'] ?? '').toString().trim(),
        title: (intent['title'] ?? '').toString().trim(),
        body: (intent['body'] ?? '').toString().trim(),
        openSource: (intent['open_source'] ?? '').toString().trim().isEmpty
            ? 'pending_notification'
            : (intent['open_source'] ?? '').toString().trim(),
      );
    }
  }

  String _buildNotificationOpenDedupKey(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    final eventId = (data['event_id'] ?? '').toString().trim();
    if (type.isNotEmpty && eventId.isNotEmpty) {
      return '$type:event:$eventId';
    }

    final inviteId = (data['invite_id'] ?? '').toString().trim();
    final planId = (data['plan_id'] ?? '').toString().trim();
    final removedUserId = (data['removed_user_id'] ?? '').toString().trim();
    final ownerUserId = (data['owner_user_id'] ?? '').toString().trim();
    final leftUserId = (data['left_user_id'] ?? '').toString().trim();
    final joinedUserId = (data['joined_user_id'] ?? '').toString().trim();

    if (type == 'PLAN_INTERNAL_INVITE' && inviteId.isNotEmpty) {
      return '$type:invite:$inviteId';
    }
    if (type == 'PLAN_MEMBER_LEFT' &&
        planId.isNotEmpty &&
        leftUserId.isNotEmpty) {
      return '$type:$planId:$leftUserId';
    }
    if (type == 'PLAN_MEMBER_REMOVED' &&
        planId.isNotEmpty &&
        removedUserId.isNotEmpty &&
        ownerUserId.isNotEmpty) {
      return '$type:$planId:$removedUserId:$ownerUserId';
    }
    if (type == 'PLAN_MEMBER_JOINED_BY_INVITE' &&
        planId.isNotEmpty &&
        joinedUserId.isNotEmpty) {
      return '$type:$planId:$joinedUserId';
    }
    if (type == 'PLAN_DELETED' && planId.isNotEmpty && ownerUserId.isNotEmpty) {
      return '$type:$planId:$ownerUserId';
    }

    const scheduledTypes = <String>{
      'PLAN_VOTING_REMINDER_DATE',
      'PLAN_VOTING_REMINDER_PLACE',
      'PLAN_VOTING_REMINDER_BOTH',
      'PLAN_OWNER_PRIORITY_DATE',
      'PLAN_OWNER_PRIORITY_PLACE',
      'PLAN_OWNER_PRIORITY_BOTH',
      'PLAN_EVENT_REMINDER_24H',
    };

    if (scheduledTypes.contains(type) && planId.isNotEmpty) {
      final eventAt = (data['event_at'] ?? '').toString().trim();
      final eventDatetimeLabel =
          (data['event_datetime_label'] ?? '').toString().trim();
      final placeTitle = (data['place_title'] ?? '').toString().trim();
      return '$type:$planId:$eventAt:$eventDatetimeLabel:$placeTitle';
    }

    return '';
  }

  bool _shouldSkipDuplicateNotificationOpen(String key) {
    final normalized = key.trim();
    if (normalized.isEmpty) return false;

    final now = DateTime.now();
    final prevKey = _lastHandledNotificationOpenKey;
    final prevAt = _lastHandledNotificationOpenAt;
    if (prevKey == normalized &&
        prevAt != null &&
        now.difference(prevAt).inSeconds < 3) {
      return true;
    }

    _lastHandledNotificationOpenKey = normalized;
    _lastHandledNotificationOpenAt = now;
    return false;
  }

  void _scheduleConsumeInboxDeliveryIfPending(Map<String, dynamic> payload) {
    final status = (payload['delivery_status'] ?? payload['status'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (status != 'PENDING') {
      return;
    }

    final deliveryId =
        (payload['delivery_id'] ?? payload['deliveryId'] ?? '').toString();
    _scheduleConsumeInboxDelivery(deliveryId);
  }

  Map<String, dynamic>? _extractPayloadMap(dynamic payloadRaw) {
    if (payloadRaw is Map) {
      return _asStringKeyedMap(payloadRaw);
    }
    if (payloadRaw is String && payloadRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadRaw);
        if (decoded is Map) {
          return _asStringKeyedMap(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic>? _normalizeInboxDeliveryRow(Map raw) {
    final id = (raw['id'] ?? raw['delivery_id'] ?? '').toString().trim();
    final status = (raw['status'] ?? '').toString().trim().toUpperCase();
    if (id.isEmpty || (status != 'PENDING' && status != 'CONSUMED')) {
      return null;
    }

    final payload = _extractPayloadMap(raw['payload']);
    if (payload == null) return null;

    payload['delivery_id'] = id;
    payload['delivery_status'] = status;

    final eventId =
        (raw['event_id'] ?? payload['event_id'] ?? payload['eventId'] ?? '')
            .toString()
            .trim();
    if (eventId.isNotEmpty) {
      payload['event_id'] = eventId;
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> _loadRecentInboxDeliveryRows({
    String? eventId,
    int limit = 80,
  }) async {
    final appUserId = _userId;
    if (appUserId == null || appUserId.trim().isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    dynamic raw;
    if ((eventId ?? '').trim().isNotEmpty) {
      raw = await _supabase
          .from('notification_deliveries')
          .select('id,event_id,status,payload,created_at')
          .eq('user_id', appUserId)
          .eq('channel', 'INBOX')
          .eq('event_id', eventId!.trim())
          .order('created_at', ascending: false)
          .limit(limit);
    } else {
      raw = await _supabase
          .from('notification_deliveries')
          .select('id,event_id,status,payload,created_at')
          .eq('user_id', appUserId)
          .eq('channel', 'INBOX')
          .order('created_at', ascending: false)
          .limit(limit);
    }

    if (raw is! List) return const <Map<String, dynamic>>[];

    final items = <Map<String, dynamic>>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final normalized = _normalizeInboxDeliveryRow(row);
      if (normalized != null) {
        items.add(normalized);
      }
    }
    return items;
  }

  bool _isOwnerResultPayload(Map<String, dynamic> payload) {
    final type = (payload['type'] ?? '').toString().trim();
    final action = (payload['action'] ??
            payload['owner_action'] ??
            payload['ownerAction'] ??
            '')
        .toString()
        .trim()
        .toUpperCase();

    return (type == 'PLAN_INTERNAL_INVITE' &&
            (action == 'ACCEPT' || action == 'DECLINE')) ||
        type == 'PLAN_INTERNAL_INVITE_ACCEPTED' ||
        type == 'PLAN_INTERNAL_INVITE_DECLINED';
  }

  bool _isInviteeInvitePayload(Map<String, dynamic> payload) {
    if (_isOwnerResultPayload(payload)) {
      return false;
    }

    final type = (payload['type'] ?? '').toString().trim();
    final inviteId =
        (payload['invite_id'] ?? payload['inviteId'] ?? '').toString().trim();
    final planId =
        (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
    final actionsRaw = payload['actions'];
    final hasActions = actionsRaw is List && actionsRaw.isNotEmpty;

    return type == 'PLAN_INTERNAL_INVITE' ||
        (inviteId.isNotEmpty && planId.isNotEmpty && hasActions);
  }

  Future<Map<String, dynamic>?> _resolveInviteOpenInboxDelivery({
    required String inviteId,
    String? planId,
  }) async {
    final iid = inviteId.trim();
    if (iid.isEmpty) return null;

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final payloadInviteId =
            (payload['invite_id'] ?? payload['inviteId'] ?? '')
                .toString()
                .trim();
        if (payloadInviteId != iid) continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        final requestedPlanId = (planId ?? '').trim();
        if (requestedPlanId.isNotEmpty &&
            payloadPlanId.isNotEmpty &&
            payloadPlanId != requestedPlanId) {
          continue;
        }

        if ((_isOwnerResultPayload(payload) ||
            _isInviteeInvitePayload(payload))) {
          if ((payload['action'] == null ||
                  payload['action'].toString().trim().isEmpty) &&
              ((payload['type'] ?? '').toString().trim() ==
                      'PLAN_INTERNAL_INVITE_ACCEPTED' ||
                  (payload['type'] ?? '').toString().trim() ==
                      'PLAN_INTERNAL_INVITE_DECLINED')) {
            payload['action'] = (payload['type'] ?? '').toString().trim() ==
                    'PLAN_INTERNAL_INVITE_ACCEPTED'
                ? 'ACCEPT'
                : 'DECLINE';
          }
          return payload;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadInboxDeliveryByEventId({
    required String eventId,
    String? expectedType,
  }) async {
    final eid = eventId.trim();
    if (eid.isEmpty) return null;

    try {
      final rows = await _loadRecentInboxDeliveryRows(eventId: eid, limit: 5);
      for (final payload in rows) {
        final type = (payload['type'] ?? '').toString().trim();
        if ((expectedType ?? '').trim().isNotEmpty && type != expectedType) {
          continue;
        }
        return payload;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlanMemberLeftInboxDelivery({
    required String planId,
    required String leftUserId,
    String? eventId,
  }) async {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      final resolved = await _loadInboxDeliveryByEventId(
        eventId: eid,
        expectedType: 'PLAN_MEMBER_LEFT',
      );
      if (resolved != null) return resolved;
    }

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final type = (payload['type'] ?? '').toString().trim();
        if (type != 'PLAN_MEMBER_LEFT') continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        final payloadLeftUserId = (payload['left_user_id'] ??
                payload['leftUserId'] ??
                payload['member_user_id'] ??
                payload['memberUserId'] ??
                '')
            .toString()
            .trim();
        if (payloadPlanId == planId.trim() &&
            payloadLeftUserId == leftUserId.trim()) {
          return payload;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlanMemberRemovedInboxDelivery({
    required String planId,
    required String removedUserId,
    required String ownerUserId,
    String? eventId,
  }) async {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      final resolved = await _loadInboxDeliveryByEventId(
        eventId: eid,
        expectedType: 'PLAN_MEMBER_REMOVED',
      );
      if (resolved != null) return resolved;
    }

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final type = (payload['type'] ?? '').toString().trim();
        if (type != 'PLAN_MEMBER_REMOVED') continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        final payloadRemovedUserId =
            (payload['removed_user_id'] ?? payload['removedUserId'] ?? '')
                .toString()
                .trim();
        final payloadOwnerUserId =
            (payload['owner_user_id'] ?? payload['ownerUserId'] ?? '')
                .toString()
                .trim();
        if (payloadPlanId == planId.trim() &&
            payloadRemovedUserId == removedUserId.trim() &&
            payloadOwnerUserId == ownerUserId.trim()) {
          return payload;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlanMemberJoinedByInviteInboxDelivery({
    required String planId,
    required String joinedUserId,
    String? eventId,
  }) async {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      final resolved = await _loadInboxDeliveryByEventId(
        eventId: eid,
        expectedType: 'PLAN_MEMBER_JOINED_BY_INVITE',
      );
      if (resolved != null) return resolved;
    }

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final type = (payload['type'] ?? '').toString().trim();
        if (type != 'PLAN_MEMBER_JOINED_BY_INVITE') continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        final payloadJoinedUserId =
            (payload['joined_user_id'] ?? payload['joinedUserId'] ?? '')
                .toString()
                .trim();
        if (payloadPlanId == planId.trim() &&
            payloadJoinedUserId == joinedUserId.trim()) {
          return payload;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlanDeletedInboxDelivery({
    required String planId,
    required String ownerUserId,
    String? eventId,
  }) async {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      final resolved = await _loadInboxDeliveryByEventId(
        eventId: eid,
        expectedType: 'PLAN_DELETED',
      );
      if (resolved != null) return resolved;
    }

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final type = (payload['type'] ?? '').toString().trim();
        if (type != 'PLAN_DELETED') continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        final payloadOwnerUserId = (payload['owner_app_user_id'] ??
                payload['owner_user_id'] ??
                payload['ownerUserId'] ??
                '')
            .toString()
            .trim();
        if (payloadPlanId == planId.trim() &&
            payloadOwnerUserId == ownerUserId.trim()) {
          return payload;
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadPlanScheduledNotificationInboxDelivery({
    required String type,
    required String planId,
    String? eventId,
    String? eventAt,
    String? eventDatetimeLabel,
    String? placeTitle,
  }) async {
    final eid = (eventId ?? '').trim();
    if (eid.isNotEmpty) {
      final resolved = await _loadInboxDeliveryByEventId(
        eventId: eid,
        expectedType: type.trim(),
      );
      if (resolved != null) return resolved;
    }

    try {
      final rows = await _loadRecentInboxDeliveryRows(limit: 80);
      for (final payload in rows) {
        final payloadType = (payload['type'] ?? '').toString().trim();
        if (payloadType != type.trim()) continue;

        final payloadPlanId =
            (payload['plan_id'] ?? payload['planId'] ?? '').toString().trim();
        if (payloadPlanId != planId.trim()) continue;

        final requestedEventAt = (eventAt ?? '').trim();
        final payloadEventAt =
            (payload['event_at'] ?? payload['eventAt'] ?? '').toString().trim();
        if (requestedEventAt.isNotEmpty &&
            payloadEventAt.isNotEmpty &&
            payloadEventAt != requestedEventAt) {
          continue;
        }

        final requestedEventDatetimeLabel = (eventDatetimeLabel ?? '').trim();
        final payloadEventDatetimeLabel = (payload['event_datetime_label'] ??
                payload['eventDatetimeLabel'] ??
                '')
            .toString()
            .trim();
        if (requestedEventDatetimeLabel.isNotEmpty &&
            payloadEventDatetimeLabel.isNotEmpty &&
            payloadEventDatetimeLabel != requestedEventDatetimeLabel) {
          continue;
        }

        final requestedPlaceTitle = (placeTitle ?? '').trim();
        final payloadPlaceTitle =
            (payload['place_title'] ?? payload['placeTitle'] ?? '')
                .toString()
                .trim();
        if (requestedPlaceTitle.isNotEmpty &&
            payloadPlaceTitle.isNotEmpty &&
            payloadPlaceTitle != requestedPlaceTitle) {
          continue;
        }

        return payload;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _handlePlanScheduledNotificationOpenFromNotificationTap({
    required String type,
    required String planId,
    String? eventId,
    String? planTitle,
    String? eventAt,
    String? eventDatetimeLabel,
    String? placeTitle,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedType = type.trim();
    final trimmedPlanId = planId.trim();
    if (trimmedType.isEmpty || trimmedPlanId.isEmpty) return;

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': trimmedType,
        'plan_id': trimmedPlanId,
        if ((eventId ?? '').trim().isNotEmpty)
          'event_id': (eventId ?? '').trim(),
        if ((planTitle ?? '').trim().isNotEmpty)
          'plan_title': (planTitle ?? '').trim(),
        if ((eventAt ?? '').trim().isNotEmpty)
          'event_at': (eventAt ?? '').trim(),
        if ((eventDatetimeLabel ?? '').trim().isNotEmpty)
          'event_datetime_label': (eventDatetimeLabel ?? '').trim(),
        if ((placeTitle ?? '').trim().isNotEmpty)
          'place_title': (placeTitle ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': trimmedType,
      'event_id': (eventId ?? '').trim(),
      'plan_id': trimmedPlanId,
      'event_at': (eventAt ?? '').trim(),
      'event_datetime_label': (eventDatetimeLabel ?? '').trim(),
      'place_title': (placeTitle ?? '').trim(),
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _loadPlanScheduledNotificationInboxDelivery(
      type: trimmedType,
      planId: trimmedPlanId,
      eventId: eventId,
      eventAt: eventAt,
      eventDatetimeLabel: eventDatetimeLabel,
      placeTitle: placeTitle,
    );

    final effective = resolved ??
        <String, dynamic>{
          'type': trimmedType,
          'plan_id': trimmedPlanId,
          if ((eventId ?? '').trim().isNotEmpty)
            'event_id': (eventId ?? '').trim(),
          if ((planTitle ?? '').trim().isNotEmpty)
            'plan_title': (planTitle ?? '').trim(),
          if ((eventAt ?? '').trim().isNotEmpty)
            'event_at': (eventAt ?? '').trim(),
          if ((eventDatetimeLabel ?? '').trim().isNotEmpty)
            'event_datetime_label': (eventDatetimeLabel ?? '').trim(),
          if ((placeTitle ?? '').trim().isNotEmpty)
            'place_title': (placeTitle ?? '').trim(),
          if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
          if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        };

    _triggerCheckAndShowModalEvents();
    _scheduleConsumeInboxDeliveryIfPending(effective);
  }

  Future<void> _handleInviteOpenFromNotificationTap({
    required String inviteId,
    required String planId,
    String? actionToken,
    String? kindHint,
    String? actionHint,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedInviteId = inviteId.trim();
    final trimmedPlanId = planId.trim();
    if (trimmedInviteId.isEmpty || trimmedPlanId.isEmpty) return;

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': 'PLAN_INTERNAL_INVITE',
        'invite_id': trimmedInviteId,
        'plan_id': trimmedPlanId,
        if ((actionToken ?? '').trim().isNotEmpty)
          'action_token': (actionToken ?? '').trim(),
        if ((kindHint ?? '').trim().isNotEmpty)
          'kind_hint': (kindHint ?? '').trim(),
        if ((actionHint ?? '').trim().isNotEmpty)
          'action_hint': (actionHint ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': 'PLAN_INTERNAL_INVITE',
      'invite_id': trimmedInviteId,
      'plan_id': trimmedPlanId,
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _resolveInviteOpenInboxDelivery(
      inviteId: trimmedInviteId,
      planId: trimmedPlanId,
    );

    if (resolved != null) {
      _triggerCheckAndShowModalEvents();
      _scheduleConsumeInboxDeliveryIfPending(resolved);
      return;
    }

    _triggerCheckAndShowModalEvents();
  }

  Future<void> _handlePlanMemberLeftOpenFromNotificationTap({
    required String planId,
    required String leftUserId,
    String? leftNickname,
    String? planTitle,
    String? eventId,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedPlanId = planId.trim();
    final trimmedLeftUserId = leftUserId.trim();
    if (trimmedPlanId.isEmpty || trimmedLeftUserId.isEmpty) return;

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': 'PLAN_MEMBER_LEFT',
        'plan_id': trimmedPlanId,
        'left_user_id': trimmedLeftUserId,
        if ((leftNickname ?? '').trim().isNotEmpty)
          'left_nickname': (leftNickname ?? '').trim(),
        if ((planTitle ?? '').trim().isNotEmpty)
          'plan_title': (planTitle ?? '').trim(),
        if ((eventId ?? '').trim().isNotEmpty)
          'event_id': (eventId ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': 'PLAN_MEMBER_LEFT',
      'event_id': (eventId ?? '').trim(),
      'plan_id': trimmedPlanId,
      'left_user_id': trimmedLeftUserId,
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _loadPlanMemberLeftInboxDelivery(
      planId: trimmedPlanId,
      leftUserId: trimmedLeftUserId,
      eventId: eventId,
    );

    _triggerCheckAndShowModalEvents();

    if (resolved != null) {
      _scheduleConsumeInboxDeliveryIfPending(resolved);
    }
  }

  Future<void> _handlePlanMemberRemovedOpenFromNotificationTap({
    required String planId,
    required String removedUserId,
    required String ownerUserId,
    String? ownerNickname,
    String? planTitle,
    String? eventId,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedPlanId = planId.trim();
    final trimmedRemovedUserId = removedUserId.trim();
    final trimmedOwnerUserId = ownerUserId.trim();
    if (trimmedPlanId.isEmpty ||
        trimmedRemovedUserId.isEmpty ||
        trimmedOwnerUserId.isEmpty) {
      return;
    }

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': 'PLAN_MEMBER_REMOVED',
        'plan_id': trimmedPlanId,
        'removed_user_id': trimmedRemovedUserId,
        'owner_user_id': trimmedOwnerUserId,
        if ((ownerNickname ?? '').trim().isNotEmpty)
          'owner_nickname': (ownerNickname ?? '').trim(),
        if ((planTitle ?? '').trim().isNotEmpty)
          'plan_title': (planTitle ?? '').trim(),
        if ((eventId ?? '').trim().isNotEmpty)
          'event_id': (eventId ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': 'PLAN_MEMBER_REMOVED',
      'event_id': (eventId ?? '').trim(),
      'plan_id': trimmedPlanId,
      'removed_user_id': trimmedRemovedUserId,
      'owner_user_id': trimmedOwnerUserId,
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _loadPlanMemberRemovedInboxDelivery(
      planId: trimmedPlanId,
      removedUserId: trimmedRemovedUserId,
      ownerUserId: trimmedOwnerUserId,
      eventId: eventId,
    );

    _triggerCheckAndShowModalEvents();

    if (resolved != null) {
      _scheduleConsumeInboxDeliveryIfPending(resolved);
    }
  }

  Future<void> _handlePlanMemberJoinedByInviteOpenFromNotificationTap({
    required String planId,
    required String joinedUserId,
    String? joinedNickname,
    String? planTitle,
    String? eventId,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedPlanId = planId.trim();
    final trimmedJoinedUserId = joinedUserId.trim();
    if (trimmedPlanId.isEmpty || trimmedJoinedUserId.isEmpty) return;

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': 'PLAN_MEMBER_JOINED_BY_INVITE',
        'plan_id': trimmedPlanId,
        'joined_user_id': trimmedJoinedUserId,
        if ((joinedNickname ?? '').trim().isNotEmpty)
          'joined_nickname': (joinedNickname ?? '').trim(),
        if ((planTitle ?? '').trim().isNotEmpty)
          'plan_title': (planTitle ?? '').trim(),
        if ((eventId ?? '').trim().isNotEmpty)
          'event_id': (eventId ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': 'PLAN_MEMBER_JOINED_BY_INVITE',
      'event_id': (eventId ?? '').trim(),
      'plan_id': trimmedPlanId,
      'joined_user_id': trimmedJoinedUserId,
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _loadPlanMemberJoinedByInviteInboxDelivery(
      planId: trimmedPlanId,
      joinedUserId: trimmedJoinedUserId,
      eventId: eventId,
    );

    _triggerCheckAndShowModalEvents();

    if (resolved != null) {
      _scheduleConsumeInboxDeliveryIfPending(resolved);
    }
  }

  Future<void> _handlePlanDeletedOpenFromNotificationTap({
    required String planId,
    required String ownerUserId,
    String? ownerNickname,
    String? planTitle,
    String? eventId,
    String? title,
    String? body,
    required String openSource,
  }) async {
    final trimmedPlanId = planId.trim();
    final trimmedOwnerUserId = ownerUserId.trim();
    if (trimmedPlanId.isEmpty || trimmedOwnerUserId.isEmpty) return;

    if (!_canResolveNotificationOpenFromInbox()) {
      _enqueueNotificationOpenIntent(<String, dynamic>{
        'type': 'PLAN_DELETED',
        'plan_id': trimmedPlanId,
        'owner_user_id': trimmedOwnerUserId,
        if ((ownerNickname ?? '').trim().isNotEmpty)
          'owner_nickname': (ownerNickname ?? '').trim(),
        if ((planTitle ?? '').trim().isNotEmpty)
          'plan_title': (planTitle ?? '').trim(),
        if ((eventId ?? '').trim().isNotEmpty)
          'event_id': (eventId ?? '').trim(),
        if ((title ?? '').trim().isNotEmpty) 'title': (title ?? '').trim(),
        if ((body ?? '').trim().isNotEmpty) 'body': (body ?? '').trim(),
        'open_source': openSource,
      });
      return;
    }

    final dedupKey = _buildNotificationOpenDedupKey(<String, dynamic>{
      'type': 'PLAN_DELETED',
      'event_id': (eventId ?? '').trim(),
      'plan_id': trimmedPlanId,
      'owner_user_id': trimmedOwnerUserId,
    });
    if (_shouldSkipDuplicateNotificationOpen(dedupKey)) {
      return;
    }

    final resolved = await _loadPlanDeletedInboxDelivery(
      planId: trimmedPlanId,
      ownerUserId: trimmedOwnerUserId,
      eventId: eventId,
    );

    _triggerCheckAndShowModalEvents();

    if (resolved != null) {
      _scheduleConsumeInboxDeliveryIfPending(resolved);
    }
  }

  Map<String, dynamic> _asStringKeyedMap(Map raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      out[k.toString()] = v;
    });
    return out;
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
              return;
            }

            if (status.isNotEmpty && status != 'PENDING') {
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
            if (deliveryId.isNotEmpty) {
              payloadMap['delivery_id'] = deliveryId;
            }

            // Canonical routing:
            // - owner-result: payload.action = ACCEPT|DECLINE  -> owner-result info modal (Close only)
            // - invitee-invite: payload.actions[] present       -> invitee modal (Accept/Decline)
            //
            // Everything else is ignored.
            final payloadType = (payloadMap['type'] ?? '').toString();

            if (payloadType.isNotEmpty &&
                payloadType != 'PLAN_INTERNAL_INVITE' &&
                payloadType != 'PLAN_INTERNAL_INVITE_ACCEPTED' &&
                payloadType != 'PLAN_INTERNAL_INVITE_DECLINED' &&
                payloadType != 'PLAN_MEMBER_LEFT' &&
                payloadType != 'PLAN_MEMBER_REMOVED' &&
                payloadType != 'PLAN_MEMBER_JOINED_BY_INVITE' &&
                payloadType != 'PLAN_DELETED' &&
                payloadType != 'PLAN_VOTING_REMINDER_DATE' &&
                payloadType != 'PLAN_VOTING_REMINDER_PLACE' &&
                payloadType != 'PLAN_VOTING_REMINDER_BOTH' &&
                payloadType != 'PLAN_OWNER_PRIORITY_DATE' &&
                payloadType != 'PLAN_OWNER_PRIORITY_PLACE' &&
                payloadType != 'PLAN_OWNER_PRIORITY_BOTH' &&
                payloadType != 'PLAN_EVENT_REMINDER_24H' &&
                payloadType != 'FRIEND_REQUEST_RECEIVED' &&
                payloadType != 'FRIEND_REQUEST_ACCEPTED' &&
                payloadType != 'FRIEND_REQUEST_DECLINED' &&
                payloadType != 'FRIEND_REMOVED' &&
                payloadType != 'ATTENTION_SIGN_ACCEPTED' &&
                payloadType != 'ATTENTION_SIGN_DECLINED') {
              return;
            }

            const scheduledTypes = <String>{
              'PLAN_VOTING_REMINDER_DATE',
              'PLAN_VOTING_REMINDER_PLACE',
              'PLAN_VOTING_REMINDER_BOTH',
              'PLAN_OWNER_PRIORITY_DATE',
              'PLAN_OWNER_PRIORITY_PLACE',
              'PLAN_OWNER_PRIORITY_BOTH',
              'PLAN_EVENT_REMINDER_24H',
            };

            if (scheduledTypes.contains(payloadType)) {
              final planId = (payloadMap['plan_id'] ??
                      payloadMap['planId'] ??
                      newRow['plan_id'] ??
                      newRow['planId'] ??
                      '')
                  .toString()
                  .trim();
              if (planId.isEmpty) return;

              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            // ✅ Separate layer: PLAN_MEMBER_LEFT -> handled via modal_event_queue.
            if (payloadType == 'PLAN_MEMBER_LEFT') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

// ✅ Separate layer: PLAN_MEMBER_JOINED_BY_INVITE -> handled via modal_event_queue.
            if (payloadType == 'PLAN_MEMBER_JOINED_BY_INVITE') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

// ✅ Separate layer: PLAN_MEMBER_REMOVED -> handled via modal_event_queue.
            if (payloadType == 'PLAN_MEMBER_REMOVED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            // ✅ Separate layer: PLAN_DELETED -> handled via modal_event_queue.
            if (payloadType == 'PLAN_DELETED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            if (payloadType == 'PLAN_INTERNAL_INVITE_ACCEPTED' ||
                payloadType == 'PLAN_INTERNAL_INVITE_DECLINED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            if (payloadType == 'FRIEND_REQUEST_RECEIVED' ||
                payloadType == 'FRIEND_REQUEST_ACCEPTED' ||
                payloadType == 'FRIEND_REQUEST_DECLINED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            if (payloadType == 'FRIEND_REMOVED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            // ✅ Attention sign accept/decline → modal from queue
            if (payloadType == 'ATTENTION_SIGN_ACCEPTED' ||
                payloadType == 'ATTENTION_SIGN_DECLINED') {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
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

            if (isOwnerResult) {
              _triggerCheckAndShowModalEvents();
              consumeIfReady();
              return;
            }

            // invitee-invite -> handled via modal_event_queue
            if (payloadMap.containsKey('action')) return;

            _triggerCheckAndShowModalEvents();
            consumeIfReady();
          } catch (e) {
            // ignore handler errors
          }
        },
      );

      _inboxInvitesChannel = channel;
      channel.subscribe((status, [error]) {
        _inboxInvitesLastStatus = status;

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
    } catch (e) {
      // ignore consume errors
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

  Future<void> _openPlanDetailsFromCurrentShell(
    String planId, {
    String? toastMessage,
  }) async {
    final userId = _userId;
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
          if (toastCtx == null || !toastCtx.mounted) return;
          await showCenterToast(toastCtx, message: toastMessage);
        });
      }
    });
  }

  void _queuePendingPlanOpen(
    String planId, {
    String? toastMessage,
  }) {
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
      unawaited(_refreshGeoAndSync());
      unawaited(_ensureDeviceTokenRegistered());
      unawaited(_sendHeartbeat());

      // If user restored while app was backgrounded, flush pending invite UI/actions.
      _schedulePendingPlanOpenIfReady();

      // Check modal event queue on resume (catches events received while app was backgrounded).
      _triggerCheckAndShowModalEvents();

      // Delayed retry: Supabase token may be stale after background, causing the
      // initial getPendingEvents RPC to fail with 401. By the time this fires,
      // the token will have been refreshed automatically.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _triggerCheckAndShowModalEvents();
      });
    }
  }

  /// Schedules a modal queue check in the next frame.
  /// Safe to call from any context — guards against unready shell/user state.
  void _triggerCheckAndShowModalEvents() {
    final userId = (_userId ?? '').trim();
    final ts = DateTime.now().toIso8601String();
    if (userId.isEmpty || !_appShellReady || _restoring) {
      debugPrint('[ModalEvents][$ts] _trigger BLOCKED: userId=${userId.isEmpty ? "EMPTY" : "ok"}, '
          'shellReady=$_appShellReady, restoring=$_restoring');
      return;
    }

    debugPrint('[ModalEvents][$ts] _trigger: scheduling check for user=$userId');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use the global navigator key context — it's always valid while the app is alive.
      // Don't rely on State.mounted: Realtime callbacks may hold a stale State reference
      // after hot-reload or auth-refresh rebuild.
      final ctx = App.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) {
        debugPrint('[ModalEvents][${DateTime.now().toIso8601String()}] _trigger postFrame: ctx=${ctx == null ? "NULL" : "unmounted"}');
        return;
      }
      unawaited(checkAndShowModalEvents(
        context: ctx,
        appUserId: userId,
        onOpenPlan: (planId) =>
            _queuePendingPlanOpen(planId, toastMessage: 'Приглашение принято'),
      ));
    });
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

    // Deferred deep link fallback: if no URI arrived (app was installed from
    // store after user visited plan-invite page), check clipboard for a
    // saved invite URL.  The web page copies the full URL before redirecting
    // to the store so that the token survives the install gap.
    if (initialUri == null) {
      await _tryReadClipboardInviteToken();
    }

    // stream (while app is running)
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      unawaited(_handleIncomingUri(uri));
    });
  }

  /// Reads clipboard looking for a centry plan-invite URL.
  /// Used as a deferred deep link fallback when the app is opened after
  /// installation from the store (no real deep link is available).
  Future<void> _tryReadClipboardInviteToken() async {
    try {
      // Skip if we already have a pending token in storage.
      final existing = await _storage.readPendingPlanInviteToken();
      if (existing != null && existing.isNotEmpty) return;

      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;

      // Only accept URLs pointing to our invite page.
      final uri = Uri.tryParse(text);
      if (uri == null) return;

      final token = _extractPlanInviteToken(uri);
      if (token == null || token.isEmpty) return;

      await _storage.writePendingPlanInviteToken(token);
      unawaited(_tryConsumePendingPlanInvite());
    } catch (_) {
      // Clipboard access may be denied — not critical.
    }
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

  Future<void> _checkLegalAcceptanceIfNeeded() async {
    final userId = _userId;
    if (userId == null) return;

    setState(() => _legalCheckInProgress = true);

    try {
      final repo = LegalRepositoryImpl(_supabase);
      final status = await repo.checkAcceptance(appUserId: userId);

      if (!mounted) return;

      if (status.needsAcceptance) {
        setState(() {
          _legalNeedsAcceptance = true;
          _legalCheckInProgress = false;
        });
      } else {
        setState(() => _legalCheckInProgress = false);
        _runPostIdentityFlows();
      }
    } catch (_) {
      // fail-open: ошибка проверки не блокирует пользователя
      if (!mounted) return;
      setState(() => _legalCheckInProgress = false);
      _runPostIdentityFlows();
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

  Future<void> _sendHeartbeat() async {
    final userId = _userId;
    if (userId == null || userId.isEmpty) return;
    try {
      await _supabase.rpc('heartbeat_v1', params: {'p_user_id': userId});
    } catch (e) {
      debugPrint('[App] heartbeat_v1 error: $e');
    }
  }

  Future<void> _refreshGeoAndSync() async {
    await GeoService.instance.refresh();
    final pos = GeoService.instance.current.value;
    final userId = _userId;
    if (pos == null || userId == null || userId.isEmpty) return;
    try {
      await _supabase.rpc('upsert_user_area_v1', params: {
        'p_app_user_id': userId,
        'p_lat': pos.lat,
        'p_lng': pos.lng,
      });
    } catch (_) {
      // Не критично — рейтинг работает без города
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
      // ignore
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

    } catch (e) {
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
          _shellGeneration++;
          _homeVisibleAt = null;
          _postIdentityFlowsRerunRequested = false;
        });
    
    
    

        unawaited(_checkLegalAcceptanceIfNeeded());
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
        _shellGeneration++;
        _homeVisibleAt = null;
        _postIdentityFlowsRerunRequested = false;
      });
  
  
  

      unawaited(_checkLegalAcceptanceIfNeeded());
      return;
    }

    // ===== ONBOARDING =====
    if (!mounted) return;
    await _disposeInboxInvitesRealtimeSubscription();
    final showVideo = await IntroVideoScreen.shouldShow();
    if (!mounted) return;
    setState(() {
      _userId = null;
      _nickname = null;
      _publicId = null;
      _email = null;
      _showIntroVideo = showVideo;
      _restoring = false;
      _appShellReady = false;
      _shellGeneration++;
      _homeVisibleAt = null;
      _welcomeCompleted = false;
      _postIdentityFlowsRerunRequested = false;
    });



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
      _welcomeCompleted = false;
      _homeVisibleAt = null;
    });




    _runPostIdentityFlows();
  }

  void _onWelcomeCompleted() {
    if (!mounted) return;
    setState(() {
      _welcomeCompleted = true;
    });
  }

  void _onAppShellReady() {
    // Инициализационные действия — только один раз (при первом вызове).
    if (!_appShellReady) {
      _appShellReady = true;

      _flushPendingConsumeInboxDeliveriesIfAny();
      _flushPendingNotificationOpenIntentsIfAny();
      _ensureInboxInvitesRealtimeSubscribed();

      _homeVisibleAt ??= DateTime.now();
      unawaited(_sendHeartbeat());
    }

    // Modal check — ВСЕГДА, даже при повторных вызовах.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use navigator key instead of State.mounted — robust against stale callbacks.
      if (App.navigatorKey.currentContext == null) return;
      _schedulePendingPlanOpenIfReady();
      // Check modal event queue after shell is fully ready.
      _triggerCheckAndShowModalEvents();
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
      if (_legalCheckInProgress) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }

      if (_legalNeedsAcceptance) {
        return LegalAgreementScreen(
          appUserId: _userId!,
          bootstrapResult: {
            'id': _userId!,
            'public_id': _publicId!,
            'nickname': _nickname ?? '',
            'state': 'USER',
          },
          onAccepted: (_) {
            setState(() => _legalNeedsAcceptance = false);
            _runPostIdentityFlows();
          },
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _schedulePendingPlanOpenIfReady();
      });

      if (!_welcomeCompleted) {
        return HomeScreen(
          nickname: _nickname ?? '',
          onWelcomeCompleted: _onWelcomeCompleted,
        );
      }

      return ActivityFeedScreen(
        userId: _userId!,
        nickname: _nickname ?? '',
        publicId: _publicId!,
        email: _email,
        shellGeneration: _shellGeneration,
        initialPlanIdToOpen: null,
        onInitialPlanOpened: _consumePendingOpenPlanId,
        onAppShellReady: _onAppShellReady,
      );
    }

    if (_showIntroVideo) {
      return IntroVideoScreen(
        onDone: () {
          if (!mounted) return;
          setState(() => _showIntroVideo = false);
        },
      );
    }

    return NicknameScreen(
      onBootstrapped: _finishOnboarding,
    );
  }
}
