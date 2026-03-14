import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/supabase_config.dart';

/// Канал должен совпадать с MainActivity.kt
const String kInviteChannelId = 'centry_invites_v6';

/// Internal invite notification action ids (open-only canon)
const String kInviteActionOpen = 'OPEN';

class PushNotifications {
  PushNotifications._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static bool _initedUi = false;
  static bool _initedBg = false;

  static Future<void> _ensureAndroidChannelCreated() async {
    if (kIsWeb) return;

    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const channel = AndroidNotificationChannel(
      kInviteChannelId,
      'Инвайты и приглашения',
      description: 'Приглашения в планы и важные действия',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await androidPlugin.createNotificationChannel(channel);

    if (kDebugMode) {
      debugPrint('[PushNotifications] ensured channel $kInviteChannelId');
    }
  }

  static String _trimToString(dynamic v) {
    return (v ?? '').toString().trim();
  }

  static String _stripOuterQuotes(String s) {
    var t = s.trim();
    if (t.length >= 2) {
      final first = t[0];
      final last = t[t.length - 1];
      final isAngle = first == '«' && last == '»';
      final isDouble = first == '"' && last == '"';
      final isCurly = first == '“' && last == '”';
      final isSingleCurly = first == '‘' && last == '’';
      if (isAngle || isDouble || isCurly || isSingleCurly) {
        t = t.substring(1, t.length - 1).trim();
      }
    }
    return t;
  }

  static String _quoteNickname(String nickname) {
    final bare = _stripOuterQuotes(nickname);
    if (bare.isEmpty) return '';
    return '«$bare»';
  }

  static String? _extractAnyNickname(Map<String, dynamic> data) {
    const keys = <String>[
      'nickname',
      'user_nickname',
      'userNickname',
      'from_nickname',
      'fromNickname',
      'from_user_nickname',
      'fromUserNickname',
      'requester_nickname',
      'requesterNickname',
      'inviter_nickname',
      'inviterNickname',
      'owner_nickname',
      'ownerNickname',
      'left_nickname',
      'member_nickname',
      'memberNickname',
      'joined_nickname',
      'joinedNickname',
      'actor_nickname',
      'actorNickname',
      'by_nickname',
      'byNickname',
      'remover_nickname',
      'removerNickname',
    ];

    for (final k in keys) {
      final v = _trimToString(data[k]);
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Ensures the given nickname is always rendered in «…» quotes inside title/body.
  ///
  /// Goal: consistent UX even if server body sometimes includes raw nick without quotes.
  /// We keep this as presentation-only normalization (no product decisions).
  static String _normalizeTextWithNicknameQuotes(
      String text, String? nickname) {
    final nick = _stripOuterQuotes(nickname ?? '');
    if (nick.isEmpty) return text;

    final quoted = '«$nick»';
    final escaped = RegExp.escape(nick);

    // Boundaries: start/end OR whitespace/punctuation (excluding quote chars).
    final re = RegExp(
      '(^|[\\s\\(\\[\\{\\-—–,:;.!?])' + escaped + r'(?=$|[\s\)\]\}\-—–,:;.!?])',
      multiLine: true,
    );

    var out = text.replaceAllMapped(re, (m) => '${m.group(1)}$quoted');

    // Normalize explicit quoted variants ("nick", “nick”) to «nick».
    out = out
        .replaceAll('"$nick"', quoted)
        .replaceAll('“$nick”', quoted)
        .replaceAll('‘$nick’', quoted);

    return out;
  }

  static String? _inferLeadingNicknameFromBody(String body) {
    final s = body.trimLeft();
    if (s.isEmpty) return null;

    if (s.startsWith('«') ||
        s.startsWith('"') ||
        s.startsWith('“') ||
        s.startsWith('‘')) {
      return null;
    }

    final m = RegExp(r'^([^\s]+)\s+').firstMatch(s);
    if (m == null) return null;

    final candidate = (m.group(1) ?? '').trim();
    if (candidate.isEmpty) return null;

    final rest = s.substring(m.end).trimLeft().toLowerCase();
    if (rest.startsWith('отправил') ||
        rest.startsWith('принял') ||
        rest.startsWith('отклонил') ||
        rest.startsWith('удалил')) {
      return candidate;
    }

    return null;
  }

  /// Оставляем для совместимости/возможного использования в других потоках.
  static Future<void> respondInternalInviteByToken({
    required String actionToken,
    required String action,
  }) async {
    final token = actionToken.trim();
    final act = action.trim().toUpperCase();

    if (token.isEmpty) return;
    if (act != 'ACCEPT' && act != 'DECLINE') return;

    final base = SupabaseConfig.url.trim().replaceAll(RegExp(r'/*$'), '');
    final uri = Uri.parse(
      '$base/rest/v1/rpc/respond_plan_internal_invite_by_token_v1',
    );

    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] token rpc start action=$act token=${token.isNotEmpty}',
      );
    }

    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('apikey', SupabaseConfig.anonKey);
      req.headers.set('Authorization', 'Bearer ${SupabaseConfig.anonKey}');
      req.headers.set('Content-Type', 'application/json');

      final body = jsonEncode({
        'p_action_token': token,
        'p_action': act,
      });

      req.add(utf8.encode(body));

      final resp = await req.close();
      final responseText = await resp.transform(utf8.decoder).join();

      if (kDebugMode) {
        debugPrint(
          '[PushNotifications] token rpc status=${resp.statusCode} body=$responseText',
        );
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] token rpc failed: status=${resp.statusCode}',
          );
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> init({
    required Future<void> Function({
      required String inviteId,
      required String action,
      required String planId,
      String? actionToken,
      String? title,
      String? body,
    }) onInviteAction,

    /// Friends local notification OPEN callback (Scenario B/C). Must route via INBOX lookup in app layer.
    Future<void> Function({
      required String type,
      String? eventId,
      String? requestId,
      String? title,
      String? body,
    })? onFriendOpen,
    Future<void> Function({
      required String planId,
      required String leftUserId,
      String? eventId,
      String? leftNickname,
      String? planTitle,
      String? title,
      String? body,
    })? onPlanMemberLeftOpen,
    Future<void> Function({
      required String planId,
      required String removedUserId,
      required String ownerUserId,
      String? ownerNickname,
      String? planTitle,
      String? title,
      String? body,
    })? onPlanMemberRemovedOpen,
    Future<void> Function({
      required String planId,
      required String joinedUserId,
      String? joinedNickname,
      String? planTitle,
      String? title,
      String? body,
    })? onPlanMemberJoinedByInviteOpen,

    /// Plan deleted OPEN callback (Scenario B/C). Must route via INBOX lookup in app layer.
    Future<void> Function({
      required String planId,
      required String ownerUserId,
      String? ownerNickname,
      String? planTitle,
      String? eventId,
      String? title,
      String? body,
    })? onPlanDeletedOpen,

    /// New isolated OPEN callback for scheduled plan notifications:
    /// - PLAN_VOTING_REMINDER_*
    /// - PLAN_OWNER_PRIORITY_*
    /// - PLAN_EVENT_REMINDER_24H
    Future<void> Function({
      required String type,
      required String planId,
      String? eventId,
      String? planTitle,
      String? eventAt,
      String? eventDatetimeLabel,
      String? placeTitle,
      String? title,
      String? body,
    })? onPlanScheduledNotificationOpen,
  }) async {
    if (_initedUi) return;
    _initedUi = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    Future<void> handleResponse(NotificationResponse resp) async {
      final actionId = (resp.actionId ?? '').toString();
      if (kDebugMode) {
        debugPrint('[LocalNotifUI] actionId=$actionId payload=${resp.payload}');
      }

      // Canon: for internal invite push no product actions in system notification.
      // Both tap on body and tap on "Посмотреть" route to OPEN.
      final normalizedAction = actionId.isEmpty ? kInviteActionOpen : actionId;

      if (normalizedAction != kInviteActionOpen) {
        return;
      }

      final raw = resp.payload;
      if (raw == null || raw.isEmpty) return;

      Map<String, dynamic>? map;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) map = decoded;
        if (decoded is Map) map = Map<String, dynamic>.from(decoded);
      } catch (_) {
        map = null;
      }
      if (map == null) return;

      final kind = (map['kind'] ?? map['type'] ?? '').toString().trim();
      final planId = (map['plan_id'] ?? '').toString();
      final notifTitle = (map['title'] ?? '').toString().trim();
      final notifBody = (map['body'] ?? '').toString().trim();

      if (kind == 'PLAN_DELETED') {
        final ownerUserId =
            (map['owner_app_user_id'] ?? map['owner_user_id'] ?? '').toString();
        final ownerNickname = (map['owner_nickname'] ?? '').toString().trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();
        final eventId =
            (map['event_id'] ?? map['eventId'] ?? '').toString().trim();

        if (planId.isEmpty || ownerUserId.isEmpty) return;

        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open PLAN_DELETED plan_id=$planId owner_user_id=$ownerUserId event_id=$eventId',
          );
        }

        final cb = onPlanDeletedOpen;
        if (cb == null) return;

        await cb(
          planId: planId,
          ownerUserId: ownerUserId,
          ownerNickname: ownerNickname.isEmpty ? null : ownerNickname,
          planTitle: planTitle.isEmpty ? null : planTitle,
          eventId: eventId.isEmpty ? null : eventId,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      if (kind == 'PLAN_MEMBER_LEFT') {
        final leftUserId =
            (map['left_user_id'] ?? map['member_user_id'] ?? '').toString();
        final eventId =
            (map['event_id'] ?? map['eventId'] ?? '').toString().trim();
        final leftNickname =
            (map['left_nickname'] ?? map['member_nickname'] ?? '')
                .toString()
                .trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();
        if (planId.isEmpty || leftUserId.isEmpty) return;
        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open PLAN_MEMBER_LEFT plan_id=$planId left_user_id=$leftUserId event_id=$eventId',
          );
        }
        final cb = onPlanMemberLeftOpen;
        if (cb == null) return;
        await cb(
          planId: planId,
          leftUserId: leftUserId,
          eventId: eventId.isEmpty ? null : eventId,
          leftNickname: leftNickname.isEmpty ? null : leftNickname,
          planTitle: planTitle.isEmpty ? null : planTitle,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      if (kind == 'PLAN_MEMBER_REMOVED') {
        final removedUserId = (map['removed_user_id'] ?? '').toString();
        final ownerUserId = (map['owner_user_id'] ?? '').toString();
        final ownerNickname = (map['owner_nickname'] ?? '').toString().trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();

        if (planId.isEmpty || removedUserId.isEmpty || ownerUserId.isEmpty) {
          return;
        }

        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open PLAN_MEMBER_REMOVED plan_id=$planId removed_user_id=$removedUserId owner_user_id=$ownerUserId',
          );
        }

        final cb = onPlanMemberRemovedOpen;
        if (cb == null) return;

        await cb(
          planId: planId,
          removedUserId: removedUserId,
          ownerUserId: ownerUserId,
          ownerNickname: ownerNickname.isEmpty ? null : ownerNickname,
          planTitle: planTitle.isEmpty ? null : planTitle,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      if (kind == 'PLAN_MEMBER_JOINED_BY_INVITE') {
        final joinedUserId = (map['joined_user_id'] ?? '').toString();
        final joinedNickname = (map['joined_nickname'] ?? '').toString().trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();
        if (planId.isEmpty || joinedUserId.isEmpty) return;

        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open PLAN_MEMBER_JOINED_BY_INVITE plan_id=$planId joined_user_id=$joinedUserId',
          );
        }

        final cb = onPlanMemberJoinedByInviteOpen;
        if (cb == null) return;

        await cb(
          planId: planId,
          joinedUserId: joinedUserId,
          joinedNickname: joinedNickname.isEmpty ? null : joinedNickname,
          planTitle: planTitle.isEmpty ? null : planTitle,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      const scheduledKinds = <String>{
        'PLAN_VOTING_REMINDER_DATE',
        'PLAN_VOTING_REMINDER_PLACE',
        'PLAN_VOTING_REMINDER_BOTH',
        'PLAN_OWNER_PRIORITY_DATE',
        'PLAN_OWNER_PRIORITY_PLACE',
        'PLAN_OWNER_PRIORITY_BOTH',
        'PLAN_EVENT_REMINDER_24H',
      };

      if (scheduledKinds.contains(kind)) {
        final cb = onPlanScheduledNotificationOpen;
        if (cb == null) return;

        final eventId =
            (map['event_id'] ?? map['eventId'] ?? '').toString().trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();
        final eventAt = (map['event_at'] ?? '').toString().trim();
        final eventDatetimeLabel =
            (map['event_datetime_label'] ?? '').toString().trim();
        final placeTitle = (map['place_title'] ?? '').toString().trim();

        if (planId.isEmpty) return;

        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open scheduled kind=$kind event_id=$eventId plan_id=$planId',
          );
        }

        await cb(
          type: kind,
          planId: planId,
          eventId: eventId.isEmpty ? null : eventId,
          planTitle: planTitle.isEmpty ? null : planTitle,
          eventAt: eventAt.isEmpty ? null : eventAt,
          eventDatetimeLabel:
              eventDatetimeLabel.isEmpty ? null : eventDatetimeLabel,
          placeTitle: placeTitle.isEmpty ? null : placeTitle,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      // Friends notifications: route OPEN to app-level handler (INBOX is source of truth).
      if (kind.startsWith('FRIEND_')) {
        final cb = onFriendOpen;
        if (cb == null) return;

        final eventId =
            (map['event_id'] ?? map['eventId'] ?? '').toString().trim();
        final requestId =
            (map['request_id'] ?? map['requestId'] ?? '').toString().trim();

        if (kDebugMode) {
          debugPrint(
              '[PushNotifications] open FRIEND kind=$kind event_id=$eventId request_id=$requestId');
        }

        await cb(
          type: kind,
          eventId: eventId.isEmpty ? null : eventId,
          requestId: requestId.isEmpty ? null : requestId,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      // Chat message: tap just brings app to foreground, no navigation needed.
      if (kind == 'PLAN_CHAT_MESSAGE') return;

      // Default: internal invite / owner-result.
      final inviteId = (map['invite_id'] ?? '').toString();
      if (inviteId.isEmpty || planId.isEmpty) return;

      if (kDebugMode) {
        debugPrint(
          '[PushNotifications] open invite_id=$inviteId plan_id=$planId',
        );
      }

      await onInviteAction(
        inviteId: inviteId,
        action: kInviteActionOpen,
        planId: planId,
        actionToken: null,
        title: notifTitle.isEmpty ? null : notifTitle,
        body: notifBody.isEmpty ? null : notifBody,
      );
    }

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) async {
        await handleResponse(resp);
      },
    );

    await _ensureAndroidChannelCreated();

    final launch = await _local.getNotificationAppLaunchDetails();
    final resp = launch?.notificationResponse;
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] launchFromNotif=${launch?.didNotificationLaunchApp} hasResp=${resp != null}',
      );
    }
    if (launch?.didNotificationLaunchApp == true && resp != null) {
      await handleResponse(resp);
    }
  }

  static Future<void> initForBackground() async {
    if (_initedBg) return;
    _initedBg = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(settings);
    await _ensureAndroidChannelCreated();
    if (kDebugMode) debugPrint('[PushNotifications] initForBackground done');
  }

  static bool isInternalInvite(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'PLAN_INTERNAL_INVITE') return true;

    final inviteId = (m.data['invite_id'] ?? '').toString();
    final planId = (m.data['plan_id'] ?? '').toString();
    return inviteId.isNotEmpty && planId.isNotEmpty;
  }

  static bool isPlanMemberLeft(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'PLAN_MEMBER_LEFT') return true;

    // Important: do not fallback to generic member_user_id here.
    // PLAN_MEMBER_REMOVED payloads can also contain member-style ids,
    // which would incorrectly route the same FCM into LEFT and create
    // a second local notification with the wrong modal path.
    final planId = (m.data['plan_id'] ?? '').toString();
    final leftUserId = (m.data['left_user_id'] ?? '').toString();
    return planId.isNotEmpty && leftUserId.isNotEmpty;
  }

  static bool isPlanMemberRemoved(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'PLAN_MEMBER_REMOVED') return true;

    final planId = (m.data['plan_id'] ?? '').toString();
    final removedUserId = (m.data['removed_user_id'] ?? '').toString();
    final ownerUserId = (m.data['owner_user_id'] ?? '').toString();
    return planId.isNotEmpty &&
        removedUserId.isNotEmpty &&
        ownerUserId.isNotEmpty;
  }

  static bool isPlanMemberJoinedByInvite(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'PLAN_MEMBER_JOINED_BY_INVITE') return true;

    final planId = (m.data['plan_id'] ?? '').toString();
    final joinedUserId = (m.data['joined_user_id'] ?? '').toString();
    return planId.isNotEmpty && joinedUserId.isNotEmpty;
  }

  static bool isPlanDeleted(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString().trim();
    if (t == 'PLAN_DELETED') return true;

    // Important: do not fallback to generic owner_user_id here.
    // PLAN_MEMBER_REMOVED payloads also carry owner_user_id + plan_id,
    // which would incorrectly route the same FCM into PLAN_DELETED and
    // create a second local notification with the wrong modal path.
    final planId = (m.data['plan_id'] ?? '').toString().trim();
    final ownerAppUserId =
        (m.data['owner_app_user_id'] ?? '').toString().trim();
    return planId.isNotEmpty && ownerAppUserId.isNotEmpty;
  }

  static bool isPlanChatMessage(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString().trim();
    return t == 'PLAN_CHAT_MESSAGE';
  }

  static bool isFriendRequestReceived(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'FRIEND_REQUEST_RECEIVED') return true;

    final requestId = (m.data['request_id'] ?? '').toString();
    final fromUserId = (m.data['from_user_id'] ?? '').toString();
    return requestId.isNotEmpty && fromUserId.isNotEmpty;
  }

  static bool isFriendRequestAccepted(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    return t == 'FRIEND_REQUEST_ACCEPTED';
  }

  static bool isFriendRequestDeclined(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    return t == 'FRIEND_REQUEST_DECLINED';
  }

  static bool isPlanScheduledNotification(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString().trim();
    switch (t) {
      case 'PLAN_VOTING_REMINDER_DATE':
      case 'PLAN_VOTING_REMINDER_PLACE':
      case 'PLAN_VOTING_REMINDER_BOTH':
      case 'PLAN_OWNER_PRIORITY_DATE':
      case 'PLAN_OWNER_PRIORITY_PLACE':
      case 'PLAN_OWNER_PRIORITY_BOTH':
      case 'PLAN_EVENT_REMINDER_24H':
        return true;
      default:
        return false;
    }
  }

  static Future<void> showPlanScheduledNotification(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanScheduledNotification id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint(
        '[PushNotifications] showPlanScheduledNotification data=${m.data}',
      );
      debugPrint(
        '[PushNotifications] showPlanScheduledNotification notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!isPlanScheduledNotification(m)) return;

    final type = (m.data['type'] ?? '').toString().trim();
    final planId = (m.data['plan_id'] ?? '').toString().trim();
    if (type.isEmpty || planId.isEmpty) return;

    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'Уведомление';

    final body = (m.data['body'] ?? '').toString().trim().isNotEmpty
        ? (m.data['body'] ?? '').toString().trim()
        : 'Откройте приложение, чтобы посмотреть.';

    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();
    final planTitle = (m.data['plan_title'] ?? '').toString().trim();
    final eventAt = (m.data['event_at'] ?? '').toString().trim();
    final eventDatetimeLabel =
        (m.data['event_datetime_label'] ?? '').toString().trim();
    final placeTitle = (m.data['place_title'] ?? '').toString().trim();

    final payload = jsonEncode({
      ...m.data,
      'kind': type,
      'type': type,
      'plan_id': planId,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      if (eventAt.isNotEmpty) 'event_at': eventAt,
      if (eventDatetimeLabel.isNotEmpty)
        'event_datetime_label': eventDatetimeLabel,
      if (placeTitle.isNotEmpty) 'place_title': placeTitle,
      'title': title,
      'body': body,
    });

    final msgId = (m.messageId ?? '').toString().trim();
    final idSeed = eventId.isNotEmpty
        ? 'scheduled:$type:$eventId'
        : (msgId.isNotEmpty
            ? 'scheduled:$type:$planId:$msgId'
            : 'scheduled:$type:$planId:$eventAt:$eventDatetimeLabel:$placeTitle');
    final id = idSeed.hashCode & 0x7fffffff;

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) kind=$type planId=$planId eventId=$eventId',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, title, body, details, payload: payload);
    if (kDebugMode) {
      debugPrint('[PushNotifications] local.show done id=$id kind=$type');
    }
  }

  static Future<void> showInternalInvite(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showInternalInvite id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showInternalInvite data=${m.data}');
      debugPrint(
        '[PushNotifications] showInternalInvite notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!isInternalInvite(m)) return;

    final inviteId = (m.data['invite_id'] ?? '').toString();
    final planId = (m.data['plan_id'] ?? '').toString();
    if (inviteId.isEmpty || planId.isEmpty) return;

    final ownerAction =
        (m.data['action'] ?? '').toString().trim().toUpperCase();
    final isOwnerResult = ownerAction == 'ACCEPT' || ownerAction == 'DECLINE';

    final title = isOwnerResult
        ? (ownerAction == 'ACCEPT'
            ? 'Приглашение принято'
            : 'Приглашение отклонено')
        : 'Вас пригласили в план';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final body = rawBody.isNotEmpty
        ? rawBody
        : (isOwnerResult
            ? 'Откройте приложение, чтобы посмотреть результат.'
            : 'Откройте приложение, чтобы посмотреть приглашение.');

    final nickname = _extractAnyNickname(m.data);
    final normalizedTitle = _normalizeTextWithNicknameQuotes(title, nickname);
    final normalizedBody = _normalizeTextWithNicknameQuotes(body, nickname);

    // Payload is consumed by app routing. Keep it explicit.
    final payload = jsonEncode({
      'invite_id': inviteId,
      'plan_id': planId,
      'title': normalizedTitle,
      'body': normalizedBody,
      'kind': isOwnerResult ? 'OWNER_RESULT' : 'INVITEE_INVITE',
      if (isOwnerResult) 'action': ownerAction,
    });

    // Avoid overwriting invite notification with owner-result for the same invite id.
    final idSeed = isOwnerResult ? '$inviteId:$ownerAction' : inviteId;
    final id = idSeed.hashCode & 0x7fffffff;

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) inviteId=$inviteId kind=${isOwnerResult ? 'OWNER_RESULT' : 'INVITEE_INVITE'}',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, normalizedTitle, normalizedBody, details,
        payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }

  static Future<void> showFriendRequest(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showFriendRequest id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showFriendRequest data=${m.data}');
    }

    final t = (m.data['type'] ?? '').toString();
    final isReceived = t == 'FRIEND_REQUEST_RECEIVED';
    final isAccepted = t == 'FRIEND_REQUEST_ACCEPTED';
    final isDeclined = t == 'FRIEND_REQUEST_DECLINED';
    if (!isReceived && !isAccepted && !isDeclined) return;

    // Keep title/body from server when provided.
    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : (isReceived
            ? 'Запрос в друзья'
            : (isAccepted ? 'Запрос принят' : 'Запрос отклонён'));

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final body = rawBody.isNotEmpty
        ? rawBody
        : (isReceived
            ? 'Откройте приложение, чтобы ответить.'
            : 'Откройте приложение, чтобы посмотреть.');

    final extractedNickname = _extractAnyNickname(m.data);
    final nickname = extractedNickname ?? _inferLeadingNicknameFromBody(body);
    final normalizedTitle = _normalizeTextWithNicknameQuotes(title, nickname);
    final normalizedBody = _normalizeTextWithNicknameQuotes(body, nickname);

    final requestId = (m.data['request_id'] ?? '').toString();
    final idSeed = requestId.isNotEmpty
        ? 'friend:$t:$requestId'
        : 'friend:$t:${m.messageId ?? ''}';
    final id = idSeed.hashCode & 0x7fffffff;

    // ✅ Correlation keys (server adds these in data-only push)
    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();

    final payload = jsonEncode({
      'kind': t,
      'type': t,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      if (requestId.isNotEmpty) 'request_id': requestId,
      ...m.data,
      'title': normalizedTitle,
      'body': normalizedBody,
    });

    await _local.cancel(id);

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, normalizedTitle, normalizedBody, details,
        payload: payload);
    if (kDebugMode)
      debugPrint('[PushNotifications] local.show done id=$id kind=$t');
  }

  static Future<void> showFriendRemoved(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showFriendRemoved id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showFriendRemoved data=${m.data}');
    }

    final t = (m.data['type'] ?? '').toString();
    if (t != 'FRIEND_REMOVED') return;

    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'Вас удалили из друзей';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final body =
        rawBody.isNotEmpty ? rawBody : 'Откройте приложение, чтобы посмотреть.';

    final extractedNickname = _extractAnyNickname(m.data);
    final nickname = extractedNickname ?? _inferLeadingNicknameFromBody(body);
    final normalizedTitle = _normalizeTextWithNicknameQuotes(title, nickname);
    final normalizedBody = _normalizeTextWithNicknameQuotes(body, nickname);

    // ✅ Correlation keys (server adds these in data-only push)
    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();

    final idSeed = eventId.isNotEmpty
        ? 'friend:FRIEND_REMOVED:$eventId'
        : 'friend:FRIEND_REMOVED:${m.messageId ?? ''}';
    final id = idSeed.hashCode & 0x7fffffff;

    final payload = jsonEncode({
      'kind': t,
      'type': t,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      ...m.data,
      'title': normalizedTitle,
      'body': normalizedBody,
    });

    await _local.cancel(id);

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, normalizedTitle, normalizedBody, details,
        payload: payload);
    if (kDebugMode)
      debugPrint('[PushNotifications] local.show done id=$id kind=$t');
  }

  static Future<void> showPlanDeleted(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanDeleted id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showPlanDeleted data=${m.data}');
      debugPrint(
        '[PushNotifications] showPlanDeleted notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!isPlanDeleted(m)) return;

    final planId = (m.data['plan_id'] ?? '').toString();
    final ownerUserId =
        (m.data['owner_app_user_id'] ?? m.data['owner_user_id'] ?? '')
            .toString();
    if (planId.isEmpty || ownerUserId.isEmpty) return;

    final ownerNickname = (m.data['owner_nickname'] ?? '').toString().trim();
    final planTitle =
        (m.data['plan_title'] ?? m.data['plan_name'] ?? '').toString().trim();

    // Canon: title/body should come from server; fallbacks are only for safety.
    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'План был удален';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final computedBody = rawBody.isNotEmpty
        ? rawBody
        : (() {
            if (ownerNickname.isNotEmpty && planTitle.isNotEmpty) {
              return 'Пользователь ${_quoteNickname(ownerNickname)} удалил план «$planTitle».';
            }
            if (planTitle.isNotEmpty) {
              return 'План «$planTitle» был удален.';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    final nickname = ownerNickname.isNotEmpty
        ? ownerNickname
        : (_extractAnyNickname(m.data) ??
            _inferLeadingNicknameFromBody(computedBody) ??
            '');
    final normalizedTitle = _normalizeTextWithNicknameQuotes(title, nickname);
    final normalizedBody =
        _normalizeTextWithNicknameQuotes(computedBody, nickname);

    // ✅ Correlation keys (server may add these in data-only push)
    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();

    final msgId = (m.messageId ?? '').toString();
    final idSeed = eventId.isNotEmpty
        ? 'plan_deleted:$planId:$eventId'
        : (msgId.isNotEmpty
            ? 'plan_deleted:$planId:$msgId'
            : 'plan_deleted:$planId');
    final id = idSeed.hashCode & 0x7fffffff;

    final payload = jsonEncode({
      ...m.data,
      'kind': 'PLAN_DELETED',
      'type': 'PLAN_DELETED',
      'plan_id': planId,
      'owner_app_user_id': ownerUserId,
      if (ownerNickname.isNotEmpty) 'owner_nickname': ownerNickname,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      'title': normalizedTitle,
      'body': normalizedBody,
    });

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) kind=PLAN_DELETED planId=$planId ownerUserId=$ownerUserId eventId=$eventId',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, normalizedTitle, normalizedBody, details,
        payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }

  static Future<void> showPlanMemberLeft(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanMemberLeft id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showPlanMemberLeft data=${m.data}');
      debugPrint(
        '[PushNotifications] showPlanMemberLeft notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!isPlanMemberLeft(m)) return;

    final planId = (m.data['plan_id'] ?? '').toString();
    final leftUserId =
        (m.data['left_user_id'] ?? m.data['member_user_id'] ?? '').toString();
    if (planId.isEmpty || leftUserId.isEmpty) return;

    final leftNickname =
        (m.data['left_nickname'] ?? m.data['member_nickname'] ?? '')
            .toString()
            .trim();
    final planTitle =
        (m.data['plan_title'] ?? m.data['plan_name'] ?? '').toString().trim();
    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();

    // Canon: title/body should come from server; fallbacks are only for safety.
    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'Участник покинул план';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final computedBody = rawBody.isNotEmpty
        ? rawBody
        : (() {
            if (leftNickname.isNotEmpty && planTitle.isNotEmpty) {
              return '${_quoteNickname(leftNickname)} покинул(а) план "$planTitle".';
            }
            if (leftNickname.isNotEmpty) {
              return '${_quoteNickname(leftNickname)} покинул(а) план.';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    final normalizedBody =
        _normalizeTextWithNicknameQuotes(computedBody, leftNickname);

    final payload = jsonEncode({
      ...m.data,
      'kind': 'PLAN_MEMBER_LEFT',
      'type': 'PLAN_MEMBER_LEFT',
      'plan_id': planId,
      'left_user_id': leftUserId,
      if (leftNickname.isNotEmpty) 'left_nickname': leftNickname,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      'title': title,
      'body': normalizedBody,
    });

    final msgId = (m.messageId ?? '').toString();
    final idSeed = eventId.isNotEmpty
        ? 'left:$planId:$eventId'
        : (msgId.isNotEmpty
            ? 'left:$planId:$leftUserId:$msgId'
            : 'left:$planId:$leftUserId');
    final id = idSeed.hashCode & 0x7fffffff;

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) kind=PLAN_MEMBER_LEFT planId=$planId leftUserId=$leftUserId',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, title, normalizedBody, details, payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }

  static Future<void> showPlanMemberRemoved(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanMemberRemoved id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showPlanMemberRemoved data=${m.data}');
      debugPrint(
        '[PushNotifications] showPlanMemberRemoved notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!PushNotifications.isPlanMemberRemoved(m)) return;

    final planId = (m.data['plan_id'] ?? '').toString();
    final removedUserId = (m.data['removed_user_id'] ?? '').toString();
    final ownerUserId = (m.data['owner_user_id'] ?? '').toString();
    if (planId.isEmpty || removedUserId.isEmpty || ownerUserId.isEmpty) return;

    final ownerNickname =
        (m.data['owner_nickname'] ?? m.data['ownerName'] ?? '')
            .toString()
            .trim();
    final planTitle =
        (m.data['plan_title'] ?? m.data['plan_name'] ?? '').toString().trim();

    // Canon: title/body should come from server; fallbacks are only for safety.
    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'Вас удалили из плана';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final computedBody = rawBody.isNotEmpty
        ? rawBody
        : (() {
            if (ownerNickname.isNotEmpty && planTitle.isNotEmpty) {
              return 'Создатель ${_quoteNickname(ownerNickname)} удалил вас из плана «$planTitle».';
            }
            if (ownerNickname.isNotEmpty) {
              return 'Создатель ${_quoteNickname(ownerNickname)} удалил вас из плана.';
            }
            if (planTitle.isNotEmpty) {
              return 'Создатель удалил вас из плана «$planTitle».';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    final normalizedBody =
        _normalizeTextWithNicknameQuotes(computedBody, ownerNickname);

    final payload = jsonEncode({
      'kind': 'PLAN_MEMBER_REMOVED',
      'plan_id': planId,
      'removed_user_id': removedUserId,
      'owner_user_id': ownerUserId,
      if (ownerNickname.isNotEmpty) 'owner_nickname': ownerNickname,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      'title': title,
      'body': normalizedBody,
    });

    final msgId = (m.messageId ?? '').toString();
    final idSeed = msgId.isNotEmpty
        ? 'removed:$planId:$removedUserId:$msgId'
        : 'removed:$planId:$removedUserId';
    final id = idSeed.hashCode & 0x7fffffff;

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) kind=PLAN_MEMBER_REMOVED planId=$planId removedUserId=$removedUserId ownerUserId=$ownerUserId',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, title, normalizedBody, details, payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }

  static Future<void> showPlanMemberJoinedByInvite(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanMemberJoinedByInvite id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint(
          '[PushNotifications] showPlanMemberJoinedByInvite data=${m.data}');
      debugPrint(
        '[PushNotifications] showPlanMemberJoinedByInvite notificationTitle=${m.notification?.title} notificationBody=${m.notification?.body}',
      );
    }

    if (!isPlanMemberJoinedByInvite(m)) return;

    final planId = (m.data['plan_id'] ?? '').toString();
    final joinedUserId = (m.data['joined_user_id'] ?? '').toString();
    if (planId.isEmpty || joinedUserId.isEmpty) return;

    final joinedNickname = (m.data['joined_nickname'] ?? '').toString().trim();
    final planTitle =
        (m.data['plan_title'] ?? m.data['plan_name'] ?? '').toString().trim();

    // Canon: title/body should come from server; fallbacks are only for safety.
    final title = (m.data['title'] ?? '').toString().trim().isNotEmpty
        ? (m.data['title'] ?? '').toString().trim()
        : 'Участник вступил в план по Invite';

    final rawBody = (m.data['body'] ?? '').toString().trim();
    final computedBody = rawBody.isNotEmpty
        ? rawBody
        : (() {
            if (joinedNickname.isNotEmpty && planTitle.isNotEmpty) {
              return 'Участник ${_quoteNickname(joinedNickname)} вступил в план «$planTitle» по Invite';
            }
            if (joinedNickname.isNotEmpty) {
              return 'Участник ${_quoteNickname(joinedNickname)} вступил в план по Invite';
            }
            if (planTitle.isNotEmpty) {
              return 'Участник вступил в план «$planTitle» по Invite';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    final normalizedBody =
        _normalizeTextWithNicknameQuotes(computedBody, joinedNickname);

    final payload = jsonEncode({
      'kind': 'PLAN_MEMBER_JOINED_BY_INVITE',
      'plan_id': planId,
      'joined_user_id': joinedUserId,
      if (joinedNickname.isNotEmpty) 'joined_nickname': joinedNickname,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      'title': title,
      'body': normalizedBody,
    });

    final msgId = (m.messageId ?? '').toString();
    final idSeed = msgId.isNotEmpty
        ? 'joined_by_invite:$planId:$joinedUserId:$msgId'
        : 'joined_by_invite:$planId:$joinedUserId';
    final id = idSeed.hashCode & 0x7fffffff;

    await _local.cancel(id);
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] local.cancel($id) then show($id) kind=PLAN_MEMBER_JOINED_BY_INVITE planId=$planId joinedUserId=$joinedUserId',
      );
    }

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, title, normalizedBody, details, payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }

  static Future<void> showPlanChatMessage(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint(
        '[PushNotifications] showPlanChatMessage id=${m.messageId} sentAt=${m.sentTime}',
      );
      debugPrint('[PushNotifications] showPlanChatMessage data=${m.data}');
    }

    if (!isPlanChatMessage(m)) return;

    final planId = (m.data['plan_id'] ?? '').toString().trim();

    const title = 'Сообщение';
    const body =
        'У вас в чате плана новое сообщение. Откройте приложение чтобы посмотреть.';

    final eventId =
        (m.data['event_id'] ?? m.data['eventId'] ?? '').toString().trim();
    final pushDeliveryId =
        (m.data['push_delivery_id'] ?? m.data['pushDeliveryId'] ?? '')
            .toString()
            .trim();

    final msgId = (m.messageId ?? '').toString();
    final idSeed = eventId.isNotEmpty
        ? 'plan_chat_message:$planId:$eventId'
        : (msgId.isNotEmpty
            ? 'plan_chat_message:$planId:$msgId'
            : 'plan_chat_message:$planId');
    final id = idSeed.hashCode & 0x7fffffff;

    final payload = jsonEncode({
      ...m.data,
      'kind': 'PLAN_CHAT_MESSAGE',
      'type': 'PLAN_CHAT_MESSAGE',
      if (planId.isNotEmpty) 'plan_id': planId,
      if (eventId.isNotEmpty) 'event_id': eventId,
      if (pushDeliveryId.isNotEmpty) 'push_delivery_id': pushDeliveryId,
      'title': title,
      'body': body,
    });

    await _local.cancel(id);

    const android = AndroidNotificationDetails(
      kInviteChannelId,
      'Инвайты и приглашения',
      channelDescription: 'Приглашения в планы и важные действия',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: false,
      ongoing: false,
      autoCancel: true,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kInviteActionOpen,
          'Посмотреть',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
    );

    const details = NotificationDetails(android: android, iOS: ios);

    await _local.show(id, title, body, details, payload: payload);
    if (kDebugMode) {
      debugPrint('[PushNotifications] showPlanChatMessage local.show done id=$id');
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (kDebugMode) {
      debugPrint(
          '[FCM-BG] received id=${message.messageId} sentAt=${message.sentTime}');
      debugPrint('[FCM-BG] data=${message.data}');
      debugPrint(
        '[FCM-BG] notificationTitle=${message.notification?.title} notificationBody=${message.notification?.body}',
      );
    }
    await Firebase.initializeApp();
    await PushNotifications.initForBackground();
    await PushNotifications.showInternalInvite(message);
    await PushNotifications.showPlanMemberLeft(message);
    await PushNotifications.showPlanMemberRemoved(message);
    await PushNotifications.showPlanMemberJoinedByInvite(message);
    await PushNotifications.showPlanDeleted(message);
    await PushNotifications.showPlanScheduledNotification(message);
    await PushNotifications.showFriendRequest(message);
    await PushNotifications.showFriendRemoved(message);
    await PushNotifications.showPlanChatMessage(message);
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM-BG] error: $e');
  }
}
