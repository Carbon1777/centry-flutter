import 'dart:convert';
import 'dart:io';
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
      final isCurly = first == '\u201c' && last == '\u201d';
      final isSingleCurly = first == '\u2018' && last == '\u2019';
      if (isAngle || isDouble || isCurly || isSingleCurly) {
        t = t.substring(1, t.length - 1).trim();
      }
    }
    return t;
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
      '(^|[\\s\\(\\[\\{\\-\u2014\u2013,:;.!?])$escaped(?=\$|[\\s\\)\\]\\}\\\u2014\u2013,:;.!?])',
      multiLine: true,
    );

    var out = text.replaceAllMapped(re, (m) => '${m.group(1)}$quoted');

    // Normalize explicit quoted variants ("nick", \u201cnick\u201d) to «nick».
    out = out
        .replaceAll('"$nick"', quoted)
        .replaceAll('\u201c$nick\u201d', quoted)
        .replaceAll('\u2018$nick\u2019', quoted);

    return out;
  }

  static String? _inferLeadingNicknameFromBody(String body) {
    final s = body.trimLeft();
    if (s.isEmpty) return null;

    if (s.startsWith('«') ||
        s.startsWith('"') ||
        s.startsWith('\u201c') ||
        s.startsWith('\u2018')) {
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

      await req.close();
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

    /// Callback invoked when user taps a PRIVATE_CHAT_MESSAGE push notification.
    Future<void> Function()? onPrivateChatMessageOpen,

    /// Callback invoked when user taps an ATTENTION_SIGN_RECEIVED push notification.
    Future<void> Function()? onAttentionSignOpen,
  }) async {
    if (_initedUi) return;
    _initedUi = true;

    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    Future<void> handleResponse(NotificationResponse resp) async {
      final actionId = (resp.actionId ?? '').toString();

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

        await cb(
          type: kind,
          eventId: eventId.isEmpty ? null : eventId,
          requestId: requestId.isEmpty ? null : requestId,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

      // Chat messages: tap just brings app to foreground, no navigation needed.
      if (kind == 'PLAN_CHAT_MESSAGE') return;
      if (kind == 'PRIVATE_CHAT_MESSAGE') {
        final cb = onPrivateChatMessageOpen;
        if (cb != null) await cb();
        return;
      }

      // Знак внимания: открыть Коробку.
      if (kind == 'ATTENTION_SIGN_RECEIVED') {
        final cb = onAttentionSignOpen;
        if (cb != null) await cb();
        return;
      }

      // Default: internal invite / owner-result.
      final inviteId = (map['invite_id'] ?? '').toString();
      if (inviteId.isEmpty || planId.isEmpty) return;

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
    if (launch?.didNotificationLaunchApp == true && resp != null) {
      await handleResponse(resp);
    }
  }

  static Future<void> initForBackground() async {
    if (_initedBg) return;
    _initedBg = true;

    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(settings);
    await _ensureAndroidChannelCreated();
  }

  static bool isInternalInvite(RemoteMessage m) {
    final t = (m.data['type'] ?? '').toString();
    if (t == 'PLAN_INTERNAL_INVITE') return true;

    final inviteId = (m.data['invite_id'] ?? '').toString();
    final planId = (m.data['plan_id'] ?? '').toString();
    return inviteId.isNotEmpty && planId.isNotEmpty;
  }

  static Future<void> showInternalInvite(RemoteMessage m) async {
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
  }

  static Future<void> showFriendRequest(RemoteMessage m) async {
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

    // Correlation keys (server adds these in data-only push)
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
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Все пуши теперь системные (FCM notification payload) —
  // система показывает их автоматически в background/terminated.
  // Локальные show* вызовы здесь не нужны, иначе будут дубли.
}
