# ТЗ: Внедрение Cold Start группы 2 (Москва + Питер)

## 1. Контекст

### Что уже есть (Cold Start группа 1)
- **361 пользователь** в 8 городах, 29 районах, 73 командах
- Все зарегистрированы в `cold_start_registry`, имеют `auth_user_id`, профили, фото
- Работает pg_cron job каждые 10 минут: `cold_start_tick_v1()`
- Автоматически генерируются планы, знаки внимания, принимаются/отклоняются запросы
- Расписание на 12 недель в `cold_start_plan_schedule`

### Что нужно сделать
Внедрить **250 новых пользователей** (Cold Start группа 2) из папки `cold_start2/` по тому же pipeline что и группа 1. Только Москва и Питер — усиление самых больших городов.

---

## 2. Исходные данные

### 2.1 Папка cold_start2
```
cold_start2/
├── moskva/          (10 районов)
│   ├── arbat/       Team4, Team5, Team6
│   ├── basmanniy/   Team3, Team4
│   ├── hamovniki/   Team3, Team4
│   ├── krasnoselskiy/ Team3, Team4
│   ├── meshchanskiy/  Team3, Team4
│   ├── presnenskiy/   Team4, Team5, Team6
│   ├── taganskiy/     Team5, Team6, Team7, Team8
│   ├── tverskoy/      Team5, Team6, Team7, Team8
│   ├── yakimanka/     Team2, Team3
│   └── zamoskvoreche/ Team3, Team4
│
└── sankt_peterburg/ (9 районов)
    ├── admiralteyskiy/ Team5, Team6, Team7, Team8
    ├── kalininskiy/    Team3, Team4
    ├── moskovskiy/     Team4, Team5, Team6
    ├── nevskiy/        Team3, Team4
    ├── petrogradskiy/  Team4, Team5, Team6
    ├── primorskiy/     Team3, Team4
    ├── tsentralniy/    Team5, Team6, Team7, Team8
    ├── vasileostrovskiy/ Team3, Team4
    └── vyborgskiy/     Team3, Team4
```

### 2.2 Формат папки пользователя
```
nickname_m/w (Имя)/
├── avatar.jpg       — сгенерированная аватарка (flux-2-pro)
├── photo_1.jpg      — альбомное фото (flux-kontext-pro, то же лицо)
├── photo_2.jpg
├── ...photo_N.jpg   (от 0 до 6 фото)
└── avatar.webp      — системная аватарка (если нет .jpg)
```

### 2.3 Распределение по типам (250 юзеров)

| Тип | Кол-во | Аватар | Альбом | Приватность |
|-----|--------|--------|--------|-------------|
| Пустые (нет файлов) | ~25 | нет | нет | **ЗАКРЫТЫЙ** |
| Системная аватарка (.webp) | ~25 | системная | нет | **ЗАКРЫТЫЙ** |
| Только avatar.jpg | ~20 | сгенерированная | нет | открытый |
| avatar.jpg + фото | ~180 | сгенерированная | 2-6 фото | открытый |

**Правило приватности:**
- Если в папке **нет фото** (пустая или только системная .webp) → `is_closed = true`
- Если есть **avatar.jpg** (с фото или без) → `is_closed = false`

### 2.4 Данные из имени папки
- **Ник**: часть до `_m` или `_w` (например `hawk9` из `hawk9_w (Настя)`)
- **Пол**: `_m` = male, `_w` = female
- **Имя (display_name)**: в скобках (например `Настя`)
- **Город**: из пути — `moskva` или `sankt_peterburg`
- **Район**: из пути — `arbat`, `nevskiy` и т.д.
- **Команда**: из пути — `Team4`, `Team5` и т.д.

---

## 3. Pipeline внедрения

### Шаг 1: Создать manifest.json для группы 2

По аналогии с группой 1 (`cold_start_webp/manifest.json`). Для каждого юзера:

```json
{
  "city_slug": "moskva",
  "district_slug": "arbat",
  "team_slug": "Team4",
  "folder_name": "hawk9_w (Настя)",
  "nickname": "hawk9",
  "gender": "female",
  "display_name": "Настя",
  "is_closed": false,
  "has_avatar": true,
  "age": 27,
  "rest_preferences": ["rest_format_leisure", "rest_format_walks"],
  "rest_dislikes": [],
  "photos": [
    {"filename": "avatar.jpg", "width": ..., "height": ..., "size_bytes": ...},
    {"filename": "photo_1.jpg", "width": ..., "height": ..., "size_bytes": ...}
  ]
}
```

**Генерация данных:**
- `age`: рандомно 20–35
- `gender`: из имени папки (`_m` / `_w`)
- `is_closed`: true если нет avatar.jpg, false если есть
- `rest_preferences`: рандомно 1–3 из списка:
  - `rest_format_leisure`
  - `rest_format_dining`
  - `rest_format_loud`
  - `rest_format_spontaneous`
  - `rest_format_walks`
- `rest_dislikes`: рандомно 0–1 из списка:
  - `rest_dislike_long_walks`
  - `rest_dislike_large_groups`
  - `rest_dislike_spontaneous`
- `photos`: список файлов из папки с размерами

### Шаг 2: Конвертация фото в webp

Все `.jpg` фото конвертировать в `.webp` (512px для аватаров, оригинальный размер для альбомных). По аналогии с `cold_start_webp/`.

### Шаг 3: Загрузка фото в Supabase Storage

Bucket: `profile-photos` (или тот же что используется для группы 1).
Путь: `cold_start2/{city}/{district}/{team}/{folder_name}/avatar.webp`

### Шаг 4: Создание пользователей в БД

Для **каждого** из 250 юзеров выполнить (в транзакции):

#### 4.1 Создать auth user
```sql
-- Через Supabase Admin API или напрямую
INSERT INTO auth.users (id, email, ...)
VALUES (gen_random_uuid(), 'coldstart2_{nickname}@fake.centry.app', ...);
```

#### 4.2 Создать app_user
```sql
INSERT INTO app_users (id, auth_user_id, display_name, state)
VALUES (gen_random_uuid(), <auth_user_id>, <display_name>, 'USER');
```

#### 4.3 Создать профиль
```sql
INSERT INTO user_profiles (
  user_id, nickname, name, gender, age,
  rest_preferences, rest_dislikes
) VALUES (
  <app_user_id>, <nickname>, <display_name>, <gender>, <age>,
  ARRAY[<rest_preferences>], ARRAY[<rest_dislikes>]
);
```

#### 4.4 Загрузить фото
```sql
-- Для каждого фото (avatar + альбом)
INSERT INTO profile_photos (
  id, user_id, storage_key, sort_order, status,
  width, height, mime_type, size_bytes
) VALUES (
  gen_random_uuid(), <app_user_id>, <storage_key>, <sort_order>, 'ready',
  <width>, <height>, 'image/webp', <size_bytes>
);
```

- `sort_order = 0` для аватара
- `sort_order = 1, 2, 3...` для альбомных фото

#### 4.5 Зарегистрировать в cold_start_registry
```sql
INSERT INTO cold_start_registry (
  app_user_id, auth_user_id, city_slug, district_slug,
  team_slug, folder_name, is_closed
) VALUES (
  <app_user_id>, <auth_user_id>, <city_slug>, <district_slug>,
  <team_slug>, <folder_name>, <is_closed>
);
```

### Шаг 5: Сгенерировать расписание планов

```sql
-- Добавить расписание для новых команд на оставшиеся недели
-- Нужно учесть: некоторые команды (Team4, Team5...) уже существуют в группе 1
-- Новые команды: те номера Team которых нет в группе 1 для этого района
SELECT cold_start_generate_schedule_v1(12);
```

**ВАЖНО**: Проверить что `cold_start_generate_schedule_v1` корректно обработает новые команды. Если нет — вручную заполнить `cold_start_plan_schedule` для каждой новой команды.

### Шаг 6: Выдать знаки внимания

```sql
-- Для каждого нового пользователя создать записи в user_daily_attention_signs
-- По аналогии с тем как это сделано для группы 1
-- Или дождаться что tick сам их выдаст (если есть такая логика)
```

---

## 4. Важные нюансы

### 4.1 Пересечение команд с группой 1
Группа 1 занимает Team1–Team3 в Москве и Питере. Группа 2 начинается с Team2–Team8.
**Возможное пересечение**: Team2 и Team3 в некоторых районах.

**Решение**: Проверить перед импортом. Если Team3 уже есть в `arbat` от группы 1 — группа 2 использует Team4+. Судя по структуре папок, пересечений нет (группа 2 начинается с Team3–Team8 в тех районах где группа 1 заканчивается на Team2–Team3).

Нужно явно проверить:
```sql
SELECT DISTINCT city_slug, district_slug, team_slug
FROM cold_start_registry
WHERE city_slug IN ('moskva', 'sankt_peterburg')
ORDER BY 1, 2, 3;
```

И сравнить с папками в cold_start2.

### 4.2 Город в профиле
- `moskva` → "Москва" (display name в user_profiles.city)
- `sankt_peterburg` → "Санкт-Петербург"

Проверить какой формат используется в группе 1 и использовать такой же.

### 4.3 Приватность
Пользователи с `is_closed = true`:
- Их профиль не виден другим (или виден ограниченно)
- Они всё равно участвуют в планах и знаках внимания внутри команды
- Это имитирует "живых" юзеров которые ещё не заполнили профиль

### 4.4 Аватар для юзеров с системной аватаркой
У них `avatar.webp` — системная аватарка. В `profile_photos` записываем с `storage_key` указывающим на `avatars/system/avatar_XX.webp` (тот файл что скопирован в папку). Или загружаем как обычное фото.

**Альтернатива**: не загружать фото вообще, а в `user_profiles.avatar_kind` поставить `'system'` и `avatar_url` = путь к системной аватарке. Проверить как это сделано в группе 1 для закрытых профилей.

### 4.5 Не ломать существующий контур
- `cold_start_tick_v1()` уже работает каждые 10 минут
- Новые юзеры из `cold_start_registry` должны автоматически подхватиться
- Новые записи в `cold_start_plan_schedule` должны подхватиться generate_plans
- **НЕ** нужно останавливать tick на время импорта — он обрабатывает по PENDING

---

## 5. Ожидаемый результат

После выполнения:
- **+250 пользователей** в cold start контуре (итого ~611)
- **Москва**: +~130 юзеров (было ~127, станет ~257)
- **Питер**: +~120 юзеров (было ~119, станет ~239)
- Новые команды в 19 районах МСК+СПб
- Планы начнут генериться автоматически через `cold_start_tick_v1()`
- Знаки внимания начнут отправляться автоматически
- Новые пользователи появятся в ленте обычных юзеров

---

## 6. Чеклист выполнения

- [ ] Создать manifest.json для cold_start2 (250 записей)
- [ ] Конвертировать фото в webp
- [ ] Загрузить фото в Supabase Storage
- [ ] Создать auth users (250 шт)
- [ ] Создать app_users (250 шт)
- [ ] Создать user_profiles (250 шт, с возрастом 20-35, предпочтениями)
- [ ] Создать profile_photos (для юзеров с фото)
- [ ] Заполнить cold_start_registry (250 записей)
- [ ] Проверить пересечение команд с группой 1
- [ ] Сгенерировать расписание планов для новых команд
- [ ] Проверить что tick подхватил новых юзеров
- [ ] Проверить что планы генерируются
- [ ] Проверить что юзеры видны в ленте
