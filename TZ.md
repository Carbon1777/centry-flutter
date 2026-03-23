# ТЗ: Переработка экрана «Коробка знаков внимания»

## Цель

Переработать layout экрана AttentionSignBoxScreen так, чтобы всё содержимое помещалось на экране практически любого размера без вертикального скролла. Сделать премиальный визуал.

## Текущее состояние

### Файлы
- `lib/ui/attention_signs/attention_sign_box_screen.dart` — основной UI
- `lib/data/attention_signs/attention_sign_dto.dart` — DTO
- `lib/data/attention_signs/attention_signs_repository_impl.dart` — репозиторий

### Текущий layout
- Три секции расположены **вертикально** в Column:
  1. **Накопления** — Wrap-сетка 3 колонки, стикеры 86px + счётчик `×N`
  2. **На рассмотрении** — Wrap-сетка 3 колонки, стикеры 86px + ник отправителя + кнопки принять/отклонить
  3. **Мой знак** — один большой стикер 200px по центру + текст "Пропадёт в 00:00"
- Проблема: при 6 типах знаков в накоплениях + несколько входящих → контент не влезает, появляется вертикальный скролл

## Что нужно сделать

### 1. Горизонтальная скролл-лента

Заменить вертикальные Wrap-сетки на **горизонтальные скролл-ленты** в обеих секциях:
- **Накопления**: горизонтальная лента со стикерами и счётчиками
- **На рассмотрении**: горизонтальная лента с карточками входящих знаков

### 2. Премиальная стеклянная подложка

Каждый блок (накопления / на рассмотрении) оборачивается в **стеклянную подложку**:
- Полупрозрачный голубовато-серый градиент
- Эффект глубины и прозрачности (BackdropFilter + blur)
- Скруглённые углы
- Тонкий бордер (white ~10-13% opacity)
- Премиальный вид, как frosted glass

### 3. Стрелочки-индикаторы скролла

По бокам горизонтальной ленты — **стрелочки**, показывающие направление скролла:
- Если лента в начале (крайнее левое) — только правая стрелка `>`
- Если в середине — обе стрелки `< >`
- Если в конце (крайнее правое) — только левая стрелка `<`
- Стрелки полупрозрачные, не перекрывают контент (overlay или по бокам)

### 4. Размеры элементов

- **Накопления**: стикеры и счётчики **чуть крупнее** чем сейчас (стикер ~100px вместо 86px, счётчик крупнее)
- **На рассмотрении**: стикеры текущего размера (86px), **ники чуть крупнее**
- **Мой знак**: оставить как есть (200px стикер по центру)

## Что НЕ менять

- RPC / API вызовы — не трогать
- DTO — не трогать
- Логику принятия/отклонения знаков — не трогать
- Секцию "Мой знак" — оставить как есть
- Бейджи и bus — не трогать

## Файлы для изменения

| Файл | Что делать |
|------|-----------|
| `lib/ui/attention_signs/attention_sign_box_screen.dart` | Переработка layout |

## Файлы для исследования

| Файл | Зачем |
|------|-------|
| `lib/ui/attention_signs/attention_sign_box_screen.dart` | Текущая реализация UI |
| `lib/data/attention_signs/attention_sign_dto.dart` | DTO (AttentionSignBoxDto, CollectedAttentionSignDto, IncomingAttentionSignDto, MyDailyAttentionSignDto) |

## Проверка

1. Открыть коробку → всё помещается без вертикального скролла
2. Накопления — горизонтальный скролл, стрелочки по бокам
3. На рассмотрении — горизонтальный скролл, стрелочки по бокам
4. Стеклянная подложка — премиальный вид на обоих блоках
5. Мой знак — без изменений

---

## Справка: как начислять знаки внимания для тестов

### Пользователи
| Ник | user_id |
|-----|---------|
| Alex | `1099ebcf-037e-4174-b23a-c8cba38c250c` |
| Carbon | `c5008257-0253-4ef0-9c42-558ea216af3a` |
| t1 | `d691f76b-aeb3-41f7-b9e1-da1eed058190` |

### Типы знаков (все 6)
`diamond_necklace`, `gold_watch`, `diamond_ring`, `red_ferrari`, `rose_bouquet`, `whisky_bottle`

### 1. Начислить накопления (коллекцию)

```sql
INSERT INTO user_attention_sign_collection (user_id, sign_type_id, count, updated_at)
VALUES
  ('<user_id>', 'diamond_necklace', 3, now()),
  ('<user_id>', 'gold_watch', 2, now()),
  ('<user_id>', 'diamond_ring', 5, now()),
  ('<user_id>', 'red_ferrari', 1, now()),
  ('<user_id>', 'rose_bouquet', 4, now()),
  ('<user_id>', 'whisky_bottle', 2, now())
ON CONFLICT (user_id, sign_type_id) DO UPDATE SET count = EXCLUDED.count, updated_at = now();
```

### 2. Начислить входящие на рассмотрение (submissions)

Двухшаговый процесс:

**Шаг 1** — создать daily signs (от отправителя):
```sql
INSERT INTO user_daily_attention_signs (id, user_id, sign_type_id, allocated_date, expires_at, sent_at, sent_to_user_id)
VALUES (
  gen_random_uuid(),
  '<from_user_id>',        -- кто отправляет
  'diamond_ring',           -- тип знака
  '2026-03-20',            -- уникальная дата (не должна совпадать с существующими)
  now() + interval '2 days',
  now(),
  '<to_user_id>'           -- кому отправляет
)
RETURNING id;
```

**Шаг 2** — создать submission (используя id из шага 1):
```sql
INSERT INTO attention_sign_submissions (daily_sign_id, from_user_id, to_user_id, sign_type_id, status, expires_at)
VALUES (
  '<daily_sign_id из шага 1>',
  '<from_user_id>',
  '<to_user_id>',
  'diamond_ring',
  'PENDING',
  now() + interval '2 days'
);
```

### 3. Начислить знак для подарка (ежедневный)

```sql
INSERT INTO user_daily_attention_signs (user_id, sign_type_id, allocated_date, expires_at)
VALUES ('<user_id>', 'rose_bouquet', CURRENT_DATE, CURRENT_DATE + interval '1 day')
ON CONFLICT (user_id, allocated_date) DO NOTHING;
```

**Ограничение**: один знак в день на пользователя (unique constraint на `user_id + allocated_date`).

### 4. Автоматическое распределение

Каждый день в 00:00 UTC cron job `allocate_daily_attention_signs_v1` автоматически:
- Выдаёт каждому ACTIVE пользователю случайный знак из всех 6 типов
- Истекает все PENDING submissions с прошедшим expires_at
