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
    Future<void> Function({
      required String planId,
      required String leftUserId,
      String? leftNickname,
      String? title,
      String? body,
    })? onPlanMemberLeftOpen,
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
      final normalizedAction =
          actionId.isEmpty ? kInviteActionOpen : actionId;

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

      if (kind == 'PLAN_MEMBER_LEFT') {
        final leftUserId = (map['left_user_id'] ?? map['member_user_id'] ?? '').toString();
        final leftNickname = (map['left_nickname'] ?? map['member_nickname'] ?? '').toString().trim();
        final planTitle = (map['plan_title'] ?? '').toString().trim();
        if (planId.isEmpty || leftUserId.isEmpty) return;
        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] open PLAN_MEMBER_LEFT plan_id=$planId left_user_id=$leftUserId',
          );
        }
        final cb = onPlanMemberLeftOpen;
        if (cb == null) return;
        await cb(
          planId: planId,
          leftUserId: leftUserId,
          leftNickname: leftNickname.isEmpty ? null : leftNickname,
          planTitle: planTitle.isEmpty ? null : planTitle,
          title: notifTitle.isEmpty ? null : notifTitle,
          body: notifBody.isEmpty ? null : notifBody,
        );
        return;
      }

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

    final planId = (m.data['plan_id'] ?? '').toString();
    final leftUserId = (m.data['left_user_id'] ?? m.data['member_user_id'] ?? '').toString();
    return planId.isNotEmpty && leftUserId.isNotEmpty;
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

    final ownerAction = (m.data['action'] ?? '').toString().trim().toUpperCase();
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

    // Payload is consumed by app routing. Keep it explicit.
    final payload = jsonEncode({
      'invite_id': inviteId,
      'plan_id': planId,
      'title': title,
      'body': body,
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

    await _local.show(id, title, body, details, payload: payload);
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

    final leftNickname = (m.data['left_nickname'] ?? m.data['member_nickname'] ?? '')
        .toString()
        .trim();
    final planTitle = (m.data['plan_title'] ?? m.data['plan_name'] ?? '')
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
              return '$leftNickname покинул(а) план "$planTitle".';
            }
            if (leftNickname.isNotEmpty) {
              return '$leftNickname покинул(а) план.';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    final payload = jsonEncode({
      'kind': 'PLAN_MEMBER_LEFT',
      'plan_id': planId,
      'left_user_id': leftUserId,
      if (leftNickname.isNotEmpty) 'left_nickname': leftNickname,
      'title': title,
      'body': computedBody,
    });

    final msgId = (m.messageId ?? '').toString();
    final idSeed = msgId.isNotEmpty ? 'left:$planId:$leftUserId:$msgId' : 'left:$planId:$leftUserId';
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

    await _local.show(id, title, computedBody, details, payload: payload);
    if (kDebugMode) debugPrint('[PushNotifications] local.show done id=$id');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (kDebugMode) {
      debugPrint('[FCM-BG] received id=${message.messageId} sentAt=${message.sentTime}');
      debugPrint('[FCM-BG] data=${message.data}');
      debugPrint(
        '[FCM-BG] notificationTitle=${message.notification?.title} notificationBody=${message.notification?.body}',
      );
    }
    await Firebase.initializeApp();
    await PushNotifications.initForBackground();
    await PushNotifications.showInternalInvite(message);
    await PushNotifications.showPlanMemberLeft(message);
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM-BG] error: $e');
  }
}
