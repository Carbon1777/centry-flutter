# ТЗ: Надёжная доставка модалок через серверную очередь

## Текущее состояние системы

### Все типы push-уведомлений и их модальность

| Тип | Показывает модалку? | В modal_event_queue? | Если не тапнуть пуш |
|-----|---------------------|----------------------|---------------------|
| `ATTENTION_SIGN_ACCEPTED` | ✅ диалог | ✅ да | Покажется при открытии ✅ |
| `ATTENTION_SIGN_DECLINED` | ✅ диалог | ✅ да | Покажется при открытии ✅ |
| `FRIEND_REQUEST_RECEIVED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `FRIEND_REQUEST_ACCEPTED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `FRIEND_REQUEST_DECLINED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `FRIEND_REMOVED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_INTERNAL_INVITE` | ✅ диалог (accept/decline) | ❌ нет | Теряется ❌ |
| `PLAN_DELETED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_MEMBER_LEFT` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_MEMBER_REMOVED` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_MEMBER_JOINED_BY_INVITE` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_VOTING_REMINDER_DATE` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_VOTING_REMINDER_PLACE` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_VOTING_REMINDER_BOTH` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_OWNER_PRIORITY_DATE` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_OWNER_PRIORITY_PLACE` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_OWNER_PRIORITY_BOTH` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_EVENT_REMINDER_24H` | ✅ диалог | ❌ нет | Теряется ❌ |
| `PLAN_CHAT_MESSAGE` | ❌ бейдж | — | Ок (красная точка) ✅ |
| `PRIVATE_CHAT_MESSAGE` | ❌ навигация | — | Ок (открывает чаты) ✅ |

Итого: **18 типов модальных пушей**, из которых только 2 правильно обслуживаются через очередь.

### Как сейчас работают эфемерные модалки

Все типы кроме attention signs используют in-memory паттерн:
- `_pendingFriendRequestDialogs` в `app.dart` — для FRIEND_*
- `PlanDeletedUiCoordinator`, `PlanMemberLeftUiCoordinator`, `PlanMemberRemovedUiCoordinator`, `PlanMemberJoinedByInviteUiCoordinator` — для PLAN_MEMBER_* и PLAN_DELETED
- `InviteUiCoordinator` — для PLAN_INTERNAL_INVITE
- `PlanScheduledNotificationUiCoordinator` — для PLAN_VOTING_REMINDER_*, PLAN_OWNER_PRIORITY_*, PLAN_EVENT_REMINDER_24H

При холодном старте без тапа по пушу — все эти очереди пустые, события потеряны.

### Дополнительная проблема: двойной показ для attention signs

При тапе по пушу → событие ещё `PENDING` в очереди → при resume `checkAndShowModalEvents` покажет его повторно.

### Проблема с местом вызова `checkAndShowModalEvents`

Вызывается только из `_BottomNavigationBar` — монтируется поздно, ненадёжно.

---

## Целевое поведение

1. **Каждое событие, требующее модалку, всегда пишется в `modal_event_queue` на сервере** в момент возникновения.
2. **Очередь — единственный источник истины.** Клиент не держит in-memory очередей модалок.
3. Клиент проверяет очередь: при готовности shell после холодного старта, при resume из фона, после тапа по любому пушу.
4. Каждая модалка показывается ровно один раз — сразу после показа вызывается `consume_modal_event_v1`.
5. При тапе по пушу push handler **не показывает модалку сам** — просто вызывает `checkAndShowModalEvents`.

---

## Что нужно сделать

### Сервер

#### 1. Добавить INSERT в `modal_event_queue` для каждого типа

Найти где каждое событие генерируется и добавить INSERT:

| Тип | Где добавить | Для кого |
|-----|-------------|----------|
| `FRIEND_REQUEST_RECEIVED` | `emit_friend_request_deliveries_v1` (триггер INSERT на `friend_requests`) | addressee |
| `FRIEND_REQUEST_ACCEPTED` | там же (триггер UPDATE) | requester |
| `FRIEND_REQUEST_DECLINED` | там же (триггер UPDATE) | requester |
| `FRIEND_REMOVED` | `emit_friend_removed_deliveries_v1` | пострадавший |
| `PLAN_INTERNAL_INVITE` | функция создания инвайта | addressee |
| `PLAN_DELETED` | функция удаления плана | каждый член (кроме владельца) |
| `PLAN_MEMBER_LEFT` | функция выхода из плана | владелец плана |
| `PLAN_MEMBER_REMOVED` | функция исключения | исключённый |
| `PLAN_MEMBER_JOINED_BY_INVITE` | функция принятия инвайта | владелец плана |
| `PLAN_VOTING_REMINDER_DATE/PLACE/BOTH` | cron/триггер напоминания | адресат |
| `PLAN_OWNER_PRIORITY_DATE/PLACE/BOTH` | cron/триггер | владелец плана |
| `PLAN_EVENT_REMINDER_24H` | cron/триггер | участники |

Для каждого типа — payload с минимально необходимыми данными для рендера (nickname актора, название плана, и т.д.).

#### 2. Обновить `get_pending_modal_events_v1`

Добавить обогащение `actor_nickname` и `actor_avatar_url` для всех новых типов через JOIN по `user_profiles`. Убедиться что индекс `(user_id, status)` на таблице есть.

#### 3. Для `PLAN_INTERNAL_INVITE` — добавить логику истечения

При `consume_modal_event_v1` для инвайта проверять что он ещё актуален (не истёк, не отменён). Если инвайт уже неактуален — тихо consume без показа.

### Клиент

#### 4. Убрать все in-memory координаторы модалок

Удалить (или обнулить) использование:
- `_pendingFriendRequestDialogs` + `_queueFriendRequestDialogFromRemoteMessage()` в `app.dart`
- `PlanDeletedUiCoordinator.enqueue()`
- `PlanMemberLeftUiCoordinator.enqueue()`
- `PlanMemberRemovedUiCoordinator.enqueue()`
- `PlanMemberJoinedByInviteUiCoordinator.enqueue()`
- `InviteUiCoordinator` — только если инвайт переходит на очередь; иначе оставить как есть и только добавить очередь
- `PlanScheduledNotificationUiCoordinator.enqueue()`

Вместо этого: при тапе по любому пушу-модалке вызывать `checkAndShowModalEvents`.

#### 5. Централизовать вызов `checkAndShowModalEvents`

Перенести на уровень `_AppState`:
- После готовности shell и userId
- При `AppLifecycleState.resumed`
- После обработки push tap

Убрать вызов из `_BottomNavigationBar`.

#### 6. Расширить `modal_events_checker.dart` — рендер всех типов

Добавить ветки для каждого нового типа в `_showEventModal`:

- `FRIEND_REQUEST_RECEIVED` → аватар + никнейм, «Принять» / «Отклонить» → RPC
- `FRIEND_REQUEST_ACCEPTED` → никнейм, «Закрыть»
- `FRIEND_REQUEST_DECLINED` → никнейм, «Закрыть»
- `FRIEND_REMOVED` → никнейм, «Закрыть»
- `PLAN_INTERNAL_INVITE` → название плана + от кого, «Принять» / «Отклонить» → RPC
- `PLAN_DELETED` → название плана + владелец, «Закрыть»
- `PLAN_MEMBER_LEFT` → кто вышел + план, «Закрыть»
- `PLAN_MEMBER_REMOVED` → план + кто исключил, «Закрыть»
- `PLAN_MEMBER_JOINED_BY_INVITE` → кто + план, «Закрыть»
- `PLAN_VOTING_REMINDER_*` → текст из payload, «Перейти к плану» / «Закрыть»
- `PLAN_OWNER_PRIORITY_*` → текст из payload, «Перейти к плану» / «Закрыть»
- `PLAN_EVENT_REMINDER_24H` → текст из payload, «Закрыть»

#### 7. Исключить двойной показ для attention signs

При тапе по пушу `ATTENTION_SIGN_*` — не показывать отдельную модалку из push handler, просто вызвать `checkAndShowModalEvents`.

---

## Не трогаем

- `PLAN_CHAT_MESSAGE` — бейджи, своя логика
- `PRIVATE_CHAT_MESSAGE` — навигация к списку чатов
