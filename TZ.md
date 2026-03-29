# ТЗ: Контроль качества — верификация аудита пушей, модалок и бейджей

> **Цель:** проверить все изменения, сделанные в ходе аудита. Убедиться что ничего не сломано, мёртвый код удалён полностью, живой код работает корректно.
> **Контекст:** был проведён аудит + очистка ~2800 строк мёртвого кода. Исправлен баг бейджа PlansScreen.

---

## Что было сделано (для контекста проверяющего)

### Исправление бага
- `activity_feed_screen.dart`: при возврате из PlansScreen теперь вызывается `_loadBadges()` (раньше бейдж не обновлялся)

### Удалённый мёртвый код

**push_notifications.dart** (было ~1607 строк, стало ~580):
- Удалены 10 show* методов: `showPlanScheduledNotification`, `showFriendRemoved`, `showPlanDeleted`, `showPlanMemberLeft`, `showPlanMemberRemoved`, `showPlanMemberJoinedByInvite`, `showPrivateChatMessage`, `showAttentionSignReceived`, `showAttentionSignAcceptedOrDeclined`, `showPlanChatMessage`
- Удалены is* методы: `isPlanMemberLeft`, `isPlanMemberRemoved`, `isPlanMemberJoinedByInvite`, `isPlanDeleted`, `isPlanChatMessage`, `isPrivateChatMessage`, `isFriendRequestReceived`, `isFriendRequestAccepted`, `isFriendRequestDeclined`, `isPlanScheduledNotification`
- Удалён `_quoteNickname` (использовался только в удалённых методах)
- **Оставлены:** `showInternalInvite`, `showFriendRequest`, `isInternalInvite`, `init`, `initForBackground`, `respondInternalInviteByToken`, `firebaseMessagingBackgroundHandler`, все helper-методы для nickname normalization

**Удалены 6 файлов UI-координаторов:**
- `lib/app/invite_ui_coordinator.dart` (583 строки)
- `lib/app/plan_member_left_ui_coordinator.dart` (189 строк)
- `lib/app/plan_member_removed_ui_coordinator.dart` (152 строки)
- `lib/app/plan_deleted_ui_coordinator.dart` (144 строки)
- `lib/app/plan_member_joined_by_invite_ui_coordinator.dart` (178 строк)
- `lib/app/plan_scheduled_notification_ui_coordinator.dart` (267 строк)

**app.dart — удалённый мёртвый код:**
- Все import/init/setRootUiReady вызовы 6 координаторов
- `_handleInternalInviteAction` + `_processingInviteAction` + `kInviteAcceptedToast` / `kInviteDeclinedToast`
- Friend Delivery путь: `_handleFriendDeliveryPayload`, `_handleFriendOpenFromLocalNotification`, `_enqueueFriendRequestUi`, `_flushPendingFriendRequestsIfAny`, `_flushPendingFriendOpenIntentsIfAny`, `_loadPendingFriendInboxDelivery`
- Три диалога: `_showFriendRequestReceivedDialog`, `_showFriendOwnerResultDialog`, `_showFriendRemovedDialog`
- `_acceptFriendRequest`, `_declineFriendRequest`, `_showInfoDialog`
- Поля: `_pendingFriendRequests`, `_pendingFriendOpenIntents`
- Константы: `kFriendRequestDefaultTitle`, `kFriendRequestAcceptedTitle`, `kFriendRequestDeclinedTitle`, `_kFriendDialogConstraints`
- Import: `friends_refresh_bus.dart`

---

## Задачи верификации

### 1. Компиляция и статический анализ

- [ ] **1.1** `flutter analyze` — 0 errors в изменённых файлах: `lib/push/push_notifications.dart`, `lib/app/app.dart`, `lib/ui/activity_feed/activity_feed_screen.dart`
- [ ] **1.2** `flutter build apk --debug` или `flutter run` — проект компилируется без ошибок
- [ ] **1.3** Нет битых import-ов (проверить что ни один файл не импортирует удалённые координаторы)

### 2. Проверка что живой код НЕ затронут

Убедиться что следующие методы остались и работают:

- [ ] **2.1** `push_notifications.dart` — `showInternalInvite()` вызывается в foreground handler (`app.dart`, `_initFcmForegroundMessages`)
- [ ] **2.2** `push_notifications.dart` — `showFriendRequest()` вызывается в foreground handler
- [ ] **2.3** `push_notifications.dart` — `isInternalInvite()` вызывается из `showInternalInvite()`
- [ ] **2.4** `push_notifications.dart` — `init()` с полным набором callback-ов: `onInviteAction`, `onFriendOpen`, `onPlanMemberLeftOpen`, `onPlanMemberRemovedOpen`, `onPlanMemberJoinedByInviteOpen`, `onPlanDeletedOpen`, `onPlanScheduledNotificationOpen`, `onPrivateChatMessageOpen`, `onAttentionSignOpen`
- [ ] **2.5** `push_notifications.dart` — `firebaseMessagingBackgroundHandler` существует и пустой
- [ ] **2.6** `app.dart` — `_initFcmForegroundMessages` работает: `showInternalInvite` + `showFriendRequest` + `AttentionSignsBus` + `_triggerCheckAndShowModalEvents`
- [ ] **2.7** `app.dart` — `_initFcmMessageOpenHandlers` работает: `onMessageOpenedApp` + `getInitialMessage`
- [ ] **2.8** `app.dart` — `_initAndroidNotificationIntentBridge` — все типы обрабатываются
- [ ] **2.9** `app.dart` — `_handlePendingNotificationOpenIntent` — все типы обрабатываются
- [ ] **2.10** `app.dart` — `_triggerCheckAndShowModalEvents` работает, вызывает `checkAndShowModalEvents`
- [ ] **2.11** `modal_events_checker.dart` — не изменялся, все типы обработаны

### 3. Проверка бага бейджа PlansScreen

- [ ] **3.1** Открыть приложение → получить сообщение в план-чат → бейдж «Мои планы» появляется
- [ ] **3.2** Открыть PlansScreen → вернуться → бейдж обновляется (исчез если прочитано)
- [ ] **3.3** Убедиться что `_loadBadges()` вызывается в `.then()` после `PlansScreen` (как у `PrivateChatsListScreen`)

### 4. Пуши — нет дублей (ручное тестирование)

Для КАЖДОГО типа: отправить тестовый пуш → убедиться что приходит ровно 1 пуш.

| Тип | Foreground | Background | Terminated |
|-----|:---:|:---:|:---:|
| PLAN_INTERNAL_INVITE | [ ] | [ ] | [ ] |
| PLAN_INTERNAL_INVITE_ACCEPTED | [ ] | [ ] | [ ] |
| PLAN_INTERNAL_INVITE_DECLINED | [ ] | [ ] | [ ] |
| PLAN_MEMBER_LEFT | [ ] | [ ] | [ ] |
| PLAN_MEMBER_REMOVED | [ ] | [ ] | [ ] |
| PLAN_MEMBER_JOINED_BY_INVITE | [ ] | [ ] | [ ] |
| PLAN_DELETED | [ ] | [ ] | [ ] |
| PLAN_VOTING_REMINDER_DATE | [ ] | [ ] | [ ] |
| PLAN_EVENT_REMINDER_24H | [ ] | [ ] | [ ] |
| PLAN_CHAT_MESSAGE | [ ] | [ ] | [ ] |
| PRIVATE_CHAT_MESSAGE | [ ] | [ ] | [ ] |
| FRIEND_REQUEST_RECEIVED | [ ] | [ ] | [ ] |
| FRIEND_REQUEST_ACCEPTED | [ ] | [ ] | [ ] |
| FRIEND_REQUEST_DECLINED | [ ] | [ ] | [ ] |
| FRIEND_REMOVED | [ ] | [ ] | [ ] |
| ATTENTION_SIGN_RECEIVED | [ ] | [ ] | [ ] |
| ATTENTION_SIGN_ACCEPTED | [ ] | [ ] | [ ] |
| ATTENTION_SIGN_DECLINED | [ ] | [ ] | [ ] |

### 5. Модалки — нет дублей, нет пропусков (ручное тестирование)

Для каждого типа с модалкой: вызвать сценарий → модалка показывается ровно 1 раз.

| Тип | Модалка показалась | Consume (не повторяется) | Стиль (green/red) |
|-----|:---:|:---:|:---:|
| PLAN_INTERNAL_INVITE | [ ] | [ ] | — |
| PLAN_INVITE_RESULT_FOR_OWNER (accept) | [ ] | [ ] | [ ] green |
| PLAN_INVITE_RESULT_FOR_OWNER (decline) | [ ] | [ ] | [ ] red |
| PLAN_MEMBER_LEFT | [ ] | [ ] | — |
| PLAN_MEMBER_REMOVED | [ ] | [ ] | [ ] red |
| PLAN_MEMBER_JOINED_BY_INVITE | [ ] | [ ] | — |
| PLAN_DELETED | [ ] | [ ] | — |
| PLAN_VOTING_REMINDER_* | [ ] | [ ] | — |
| PLAN_EVENT_REMINDER_24H | [ ] | [ ] | — |
| FRIEND_REQUEST_RECEIVED | [ ] | [ ] | — |
| FRIEND_REQUEST_ACCEPTED | [ ] | [ ] | [ ] green |
| FRIEND_REQUEST_DECLINED | [ ] | [ ] | [ ] red |
| FRIEND_REMOVED | [ ] | [ ] | [ ] red |
| ATTENTION_SIGN_ACCEPTED | [ ] | [ ] | [ ] green |
| ATTENTION_SIGN_DECLINED | [ ] | [ ] | [ ] red |

### 6. Навигация по тапу (ручное тестирование)

Для каждого типа: тап по пушу из background → правильная навигация.

| Тип | Ожидаемый экран | Background | Terminated |
|-----|-----------------|:---:|:---:|
| PLAN_INTERNAL_INVITE | Модалка инвайта | [ ] | [ ] |
| PLAN_MEMBER_LEFT | План | [ ] | [ ] |
| PLAN_MEMBER_REMOVED | План | [ ] | [ ] |
| PLAN_MEMBER_JOINED_BY_INVITE | План | [ ] | [ ] |
| PLAN_DELETED | — | [ ] | [ ] |
| PLAN_VOTING_REMINDER_* | План | [ ] | [ ] |
| PLAN_EVENT_REMINDER_24H | План | [ ] | [ ] |
| PRIVATE_CHAT_MESSAGE | PrivateChatsListScreen | [ ] | [ ] |
| ATTENTION_SIGN_RECEIVED | AttentionSignBoxScreen | [ ] | [ ] |
| FRIEND_* | modal_events | [ ] | [ ] |
| ATTENTION_SIGN_ACCEPTED/DECLINED | modal_events | [ ] | [ ] |

### 7. Бейджи (ручное тестирование)

- [ ] **7.1** Бейдж чата планов: появляется при новом сообщении, исчезает после открытия PlansScreen и возврата
- [ ] **7.2** Бейдж приватных чатов: появляется при новом сообщении, исчезает после открытия PrivateChatsListScreen и возврата
- [ ] **7.3** Бейдж знаков внимания (AppBar): появляется при ATTENTION_SIGN_RECEIVED, исчезает при открытии AttentionSignBoxScreen
- [ ] **7.4** Бейдж знаков внимания (профиль): то же самое на иконке подарков
- [ ] **7.5** Бейджи корректны после cold open (при запуске загружаются через polling)

### 8. Edge cases (ручное тестирование)

- [ ] **8.1** Два инвайта подряд — оба показываются как модалки
- [ ] **8.2** Пуш во время показа модалки — не теряется (показывается при следующем trigger)
- [ ] **8.3** App kill во время модалки → при следующем open модалка показывается (не consume'илась)
- [ ] **8.4** Модалка при cold open (app terminated → open → модалка из очереди)
- [ ] **8.5** Модалка при resume (app background → foreground → модалка)

---

## Критерии готовности к релизу

1. [ ] `flutter analyze` — 0 errors, 0 warnings в изменённых файлах
2. [ ] Проект компилируется и запускается
3. [ ] Все пуши приходят ровно 1 раз в каждом состоянии приложения
4. [ ] Все модалки показываются ровно 1 раз, consume'ятся, стиль корректный
5. [ ] Тап по каждому типу пуша ведёт на правильный экран/модалку
6. [ ] Бейджи обновляются корректно (появляются / исчезают)
7. [ ] Нет регрессий в несвязанных экранах (планы, друзья, чаты, профиль)
8. [ ] Удалённые файлы координаторов не импортируются нигде в проекте

---

## Файлы затронутые изменениями

| Файл | Тип изменения |
|------|--------------|
| `lib/push/push_notifications.dart` | Удаление мёртвого кода (~1000 строк) |
| `lib/app/app.dart` | Удаление мёртвого кода (~350 строк) + удаление init координаторов |
| `lib/ui/activity_feed/activity_feed_screen.dart` | Исправление бага бейджа PlansScreen |
| `lib/app/invite_ui_coordinator.dart` | УДАЛЁН |
| `lib/app/plan_member_left_ui_coordinator.dart` | УДАЛЁН |
| `lib/app/plan_member_removed_ui_coordinator.dart` | УДАЛЁН |
| `lib/app/plan_deleted_ui_coordinator.dart` | УДАЛЁН |
| `lib/app/plan_member_joined_by_invite_ui_coordinator.dart` | УДАЛЁН |
| `lib/app/plan_scheduled_notification_ui_coordinator.dart` | УДАЛЁН |
