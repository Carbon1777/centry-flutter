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

  static Map<String, dynamic>? _tryDecodeJsonObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // ignore
    }
    return null;
  }

  static Map<String, dynamic> _normalizePayloadMap(Map<String, dynamic> base) {
    // Some server stacks wrap the actual payload into a "payload" (stringified JSON) field.
    // Or nest data into {"data": {...}}. We merge it to ensure we always read canonical keys.
    final out = Map<String, dynamic>.from(base);

    void mergeIfJsonField(String key) {
      final v = out[key];
      if (v is String && v.trim().isNotEmpty) {
        final decoded = _tryDecodeJsonObject(v.trim());
        if (decoded != null) {
          // Canon: decoded payload should override shallow fields.
          out.addAll(decoded);
        }
      } else if (v is Map) {
        out.addAll(Map<String, dynamic>.from(v));
      }
    }

    mergeIfJsonField('payload');
    mergeIfJsonField('data');

    return out;
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return '';
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
      String? planTitle,
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
      final normalizedAction = actionId.isEmpty ? kInviteActionOpen : actionId;

      if (normalizedAction != kInviteActionOpen) {
        return;
      }

      final raw = resp.payload;
      if (raw == null || raw.isEmpty) return;

      Map<String, dynamic>? decodedMap;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) decodedMap = decoded;
        if (decoded is Map) decodedMap = Map<String, dynamic>.from(decoded);
      } catch (_) {
        decodedMap = null;
      }
      if (decodedMap == null) return;

      // Important: server payload can be wrapped into {"payload":"{...json...}"} or {"data":{...}}.
      final data = _normalizePayloadMap(decodedMap);

      final kind = _readString(data, const ['kind', 'type']).trim();
      final planId = _readString(data, const ['plan_id', 'planId']).trim();
      final notifTitle = _readString(data, const ['title']).trim();
      final notifBody = _readString(data, const ['body']).trim();

      if (kind == 'PLAN_MEMBER_LEFT') {
        final leftUserId = _readString(
          data,
          const [
            'left_user_id',
            'leftUserId',
            'member_user_id',
            'memberUserId'
          ],
        ).trim();
        final leftNickname = _readString(
          data,
          const [
            'left_nickname',
            'leftNickname',
            'member_nickname',
            'memberNickname'
          ],
        ).trim();
        final planTitle = _readString(
          data,
          const ['plan_title', 'planTitle', 'plan_name', 'planName'],
        ).trim();

        if (planId.isEmpty || leftUserId.isEmpty) return;

        if (kDebugMode) {
          debugPrint(
            '[LocalNotifUI] PLAN_MEMBER_LEFT open planId=$planId leftUserId=$leftUserId leftNickname="$leftNickname" planTitle="$planTitle"',
          );
        }

        await onPlanMemberLeftOpen?.call(
          planId: planId,
          leftUserId: leftUserId,
          leftNickname: leftNickname.isNotEmpty ? leftNickname : null,
          planTitle: planTitle.isNotEmpty ? planTitle : null,
          title: notifTitle.isNotEmpty ? notifTitle : null,
          body: notifBody.isNotEmpty ? notifBody : null,
        );
        return;
      }

      // Default: treat as internal invite (both invitee invite and owner result are OPEN-only).
      final inviteId =
          _readString(data, const ['invite_id', 'inviteId']).trim();
      if (inviteId.isEmpty || planId.isEmpty) return;

      final action = _readString(data, const ['action']).trim();
      final actionToken =
          _readString(data, const ['action_token', 'actionToken']).trim();

      await onInviteAction(
        inviteId: inviteId,
        action: action.isNotEmpty ? action : kInviteActionOpen,
        planId: planId,
        actionToken: actionToken.isNotEmpty ? actionToken : null,
        title: notifTitle.isNotEmpty ? notifTitle : null,
        body: notifBody.isNotEmpty ? notifBody : null,
      );
    }

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: handleResponse,
      onDidReceiveBackgroundNotificationResponse: handleResponse,
    );

    await _ensureAndroidChannelCreated();

    if (kDebugMode) debugPrint('[PushNotifications] init done (UI)');

    // Handle app launch from notification (terminated → open).
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
    final data = _normalizePayloadMap(Map<String, dynamic>.from(m.data));

    final t = _readString(data, const ['type', 'kind']).trim();
    if (t == 'PLAN_INTERNAL_INVITE') return true;

    final inviteId = _readString(data, const ['invite_id', 'inviteId']).trim();
    final planId = _readString(data, const ['plan_id', 'planId']).trim();
    return inviteId.isNotEmpty && planId.isNotEmpty;
  }

  static bool isPlanMemberLeft(RemoteMessage m) {
    final data = _normalizePayloadMap(Map<String, dynamic>.from(m.data));

    final t = _readString(data, const ['type', 'kind']).trim();
    if (t == 'PLAN_MEMBER_LEFT') return true;

    final planId = _readString(data, const ['plan_id', 'planId']).trim();
    final leftUserId = _readString(
      data,
      const ['left_user_id', 'leftUserId', 'member_user_id', 'memberUserId'],
    ).trim();

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

    final data = _normalizePayloadMap(Map<String, dynamic>.from(m.data));

    final inviteId = _readString(data, const ['invite_id', 'inviteId']).trim();
    final planId = _readString(data, const ['plan_id', 'planId']).trim();
    if (inviteId.isEmpty || planId.isEmpty) return;

    final ownerAction =
        _readString(data, const ['action']).trim().toUpperCase();
    final isOwnerResult = ownerAction == 'ACCEPT' || ownerAction == 'DECLINE';

    final title = isOwnerResult
        ? (ownerAction == 'ACCEPT'
            ? 'Приглашение принято'
            : 'Приглашение отклонено')
        : 'Вас пригласили в план';

    final rawBody = _readString(data, const ['body']).trim();
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

    final data = _normalizePayloadMap(Map<String, dynamic>.from(m.data));

    final planId = _readString(data, const ['plan_id', 'planId']).trim();
    final leftUserId = _readString(
      data,
      const ['left_user_id', 'leftUserId', 'member_user_id', 'memberUserId'],
    ).trim();

    if (planId.isEmpty || leftUserId.isEmpty) return;

    final leftNickname = _readString(
      data,
      const [
        'left_nickname',
        'leftNickname',
        'member_nickname',
        'memberNickname'
      ],
    ).trim();
    final planTitle = _readString(
      data,
      const ['plan_title', 'planTitle', 'plan_name', 'planName'],
    ).trim();

    // Canon: title/body must come from server when provided.
    final serverTitle = _readString(data, const ['title']).trim();
    final serverBody = _readString(data, const ['body']).trim();

    final title =
        serverTitle.isNotEmpty ? serverTitle : 'Участник покинул план';

    // Safety fallback only if server did not provide body.
    final computedBody = serverBody.isNotEmpty
        ? serverBody
        : (() {
            if (leftNickname.isNotEmpty && planTitle.isNotEmpty) {
              return '$leftNickname покинул(а) план "$planTitle".';
            }
            if (leftNickname.isNotEmpty) {
              return '$leftNickname покинул(а) план.';
            }
            return 'Откройте приложение, чтобы посмотреть.';
          })();

    // Local notification payload must contain canonical keys for in-app routing.
    final payload = jsonEncode({
      'kind': 'PLAN_MEMBER_LEFT',
      'type': 'PLAN_MEMBER_LEFT',
      'plan_id': planId,
      'left_user_id': leftUserId,
      if (leftNickname.isNotEmpty) 'left_nickname': leftNickname,
      if (planTitle.isNotEmpty) 'plan_title': planTitle,
      if (serverTitle.isNotEmpty) 'title': serverTitle,
      if (serverBody.isNotEmpty) 'body': serverBody,
      // Store shown text for UI safety (not product source of truth).
      'shown_title': title,
      'shown_body': computedBody,
    });

    final msgId = (m.messageId ?? '').toString();
    final idSeed = msgId.isNotEmpty
        ? 'left:$planId:$leftUserId:$msgId'
        : 'left:$planId:$leftUserId';
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
  } catch (e) {
    if (kDebugMode) debugPrint('[FCM-BG] error: $e');
  }
}
