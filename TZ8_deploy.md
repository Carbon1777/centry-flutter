# TZ8 — Заливка в базу, рейтинг, enrichment

> Сессия 3 из 4. Зависимости: TZ6 + TZ7 завершены

---

## Цель сессии

Полная замена базы мест: деактивация старых, заливка 11000+ новых в core_places с enrichment, рейтингом и мультикатегорийностью.

---

## Предварительно

Убедиться что:
- Cold start планы уже деактивированы (TZ6 предварительный шаг)
- yandex_parse_normalized.json готов
- Фото загружены на Storage, маппинг есть

---

## Шаг 1: Деактивация старых мест

```sql
UPDATE core_places SET is_active = FALSE, updated_at = NOW()
WHERE is_active = TRUE;
```
- Soft delete — данные сохраняются
- Все RPC фильтруют по is_active = TRUE — клиент перестанет видеть старые

---

## Шаг 2: Резолвинг area_id

Для каждого места определить area_id по координатам:
- Найти ближайший район из core_areas по (lat, lng) → (center_lat, center_lng)
- Haversine или простая евклидова дистанция (города не на полюсе)
- Если расстояние > порога — пометить для ревью

---

## Шаг 3: INSERT в core_places

Для каждого нормализованного места:
- id: gen_random_uuid()
- title: из normalized
- category: primary category (bar, restaurant, nightclub, hookah, karaoke, bathhouse)
- address: нормализованный
- lat, lng: из парсинга
- area_id: из шага 2
- is_active: TRUE
- created_at, updated_at: NOW()

UNIQUE INDEX на (title, address) WHERE is_active = TRUE — дубли не пролезут.

---

## Шаг 4: place_enrichment

Для каждого нового места:
- place_id: id из core_places
- website: нормализованный (с https://)
- phones: jsonb_build_array(normalized_phone)
- rating: yandex_rating
- photos: [{storage_key, is_placeholder}]
- normalized_address: из TZ6
- review_count: из парсинга (для cold start, НЕ на клиент)
- provider: 'yandex_maps_v2'

---

## Шаг 5: Мультикатегорийность

### 5.1 Проверить app_place_categories
Убедиться что есть: bar, restaurant, nightclub, hookah, karaoke, bathhouse, cinema, theatre

### 5.2 core_place_category_links
- Primary category из search_type
- Если место найдено несколько раз с разными типами → union всех типов

---

## Шаг 6: Гибридный рейтинг

### 6.1 Bootstrap votes
Формула: `rating = 3 + (likes - dislikes) * 0.2`, зажата [1, 5]

Из yandex_rating:
- `net = round((yandex_rating - 3) * 5)`
- Дизлайки рандомизированы по диапазону:
  - rating 4.8+: dislikes 0-1
  - rating 4.5-4.7: dislikes 1-3
  - rating 4.0-4.4: dislikes 2-4
  - rating < 4.0: dislikes 3-5
- `likes = net + dislikes`

### 6.2 Верификация
- computed_rating должен быть в пределах ±0.1 от yandex_rating
- Проверить 20-30 мест вручную

---

## Шаг 7: Метро (если применимо)

Города с метро: Москва, СПб, Казань, Новосибирск, Нижний Новгород
- Привязка к ближайшей станции метро по координатам
- Расстояние в метрах

---

## Выходные артефакты

1. ~11000 активных мест в core_places
2. Полный enrichment с фото, телефонами, сайтами
3. Рейтинг через bootstrap_votes
4. Мультикатегорийность через category_links
5. Старые места деактивированы (soft delete)

---

## Supabase
- project_id: lqgzvolirohuettizkhx
