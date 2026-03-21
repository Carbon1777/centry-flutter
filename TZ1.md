ТЗ: обновление и дозагрузка мест из новых итоговых CSV в действующую БД Centry
1. Цель

Нужно провести серверную процедуру, которая возьмёт новые итоговые CSV-файлы по Москве и Санкт-Петербургу, сопоставит их с уже существующими местами в БД, обновит более актуальные данные, корректно привяжет реальные фото, а для мест без реальных фото назначит category-placeholder.

Процедура должна:

не ломать текущий продуктовый контракт;
не менять структуру core_places;
использовать текущую модель, где:
базовые данные места живут в core_places,
обогащение живёт в place_enrichment,
фото для клиента идут через place_enrichment.photos,
доп. типы места хранятся через core_place_category_links.
2. Входные данные
2.1. Входные CSV

На вход подаются 2 итоговых файла:

moscow_places_ready_geocoded_processed.csv
spb_places_ready_geocoded_processed.csv
2.2. Формат CSV

По факту текущие файлы имеют колонки:

title
address
lat
lng
type
tag
rating
phone
website
image_tag
2.3. Что означают поля
title — актуальное название места
address — актуальный адрес
lat, lng — актуальные координаты
type — тип заведения, может быть один или несколько через запятую
tag — служебный текстовый тег из старого пайплайна
rating — рейтинг
phone — телефон
website — сайт
image_tag — ключ имени фото, по которому уже названы реальные загруженные фото в storage
3. Текущий серверный контракт, который нельзя ломать
3.1. Базовые места

Основная таблица мест:

public.core_places

Её структуру не менять.

3.2. Enrichment

Финальный enrichment-слой:

public.place_enrichment

Это основной 1:1 слой по place_id.

3.3. Фото

Фото для клиента сейчас пробрасываются через:

public.get_place_details_meta_v1(p_place_id)

Источник фото:

поле public.place_enrichment.photos

Формат photos:

или placeholder:

3.4. Мультикатегорийность

Дополнительные типы места должны храниться через:

public.core_place_category_links

Справочник категорий:

public.app_place_categories
4. Что должно делать решение

Процедура должна обработать каждую строку входных CSV и для каждого места выполнить одно из двух действий:

Вариант A — место уже существует в БД

Если место уже есть в базе и уверенно матчится с записью из CSV:

не создавать новый core_places
обновить существующее место более актуальными данными из CSV
обновить enrichment
обновить типы
обновить/привязать фото
Вариант B — места в БД ещё нет

Если место не найдено:

создать новый core_places
создать/обновить place_enrichment
создать category links
привязать реальное фото или placeholder
5. Правила матчинга CSV ↔ существующая БД
5.1. Главный ключ матчинга

Матчинг должен идти по:

normalized_title
normalized_address
5.2. Нормализация title

Нужно:

lowercase
trim
заменить ё → е
схлопнуть повторные пробелы
убрать кавычки и декоративные символы
привести тире/дефисы к одному виду
убрать хвосты вида:
лишние пробелы
обрамляющие кавычки
дублирующие спецсимволы
5.3. Нормализация address

Нужно:

lowercase
trim
ё → е
убрать префикс города:
Москва,
Санкт-Петербург,
СПб,
схлопнуть пробелы
привести сокращения к каноническому сравнению:
ул. = улица
просп. = проспект
пр. = проспект/проезд по существующей логике
пр-д = проезд
ш. = шоссе
наб. = набережная
пер. = переулок
бул. = бульвар
корп. = корпус
стр. = строение
корректно понимать формы:
56к2с1
11/31
89.1
1-я ...
2-й квартал ...
5.4. Критерий совпадения

Автоматический матч допустим, если:

normalized title совпадает точно или почти точно по текущей логике
normalized address совпадает по улице и дому
корпус/строение учитываются как плюс, но их отсутствие не должно ломать матч, если улица + дом совпали
5.5. Конфликты

Если по одной входной строке найдено более одного кандидата в БД:

автообновление не делать
строку отправить в manual review / conflict list
пропустить до ручной проверки
6. Что обновлять в существующем core_places

Если место уже найдено в БД, входной CSV считается более актуальным источником.

Нужно обновлять в core_places:

title ← из CSV
address ← из CSV
lat ← из CSV
lng ← из CSV
updated_at ← now()
Важно
id не менять
area_id не менять автоматически, если нет отдельного валидного area-resolver
source_name, source_url, created_at не ломать
popularity_tier не менять этой процедурой
7. Что обновлять в place_enrichment

Для matched place обновить или создать строку в place_enrichment.

7.1. Если запись уже есть

Обновить:

website
rating
phones
photos
normalized_address
updated_at
7.2. Если записи нет

Создать новую строку:

place_id = id matched/new place
provider = 'internal'
provider_place_id = null
matched = false
match_score = null
normalized_address = нормализованный адрес
website = из CSV
rating = из CSV
rating_count = null
photos = см. раздел фото
phones = см. ниже
working_hours = null
metro = null
metro_distance_m = null
raw_response = null
created_at = now()
updated_at = now()
7.3. Правила обновления отдельных enrichment-полей
Если в CSV поле не пустое — оно приоритетнее старого
Если в CSV пусто — не затирать существующее непустое значение
Не обнулять enrichment пустыми значениями из CSV
7.4. Формат phones

Если в CSV есть phone, записывать в place_enrichment.phones как JSON-массив, например:

Если телефонов несколько — массив из нескольких значений.

8. Фото: как должно работать
8.1. Где уже лежат реальные фото

Реальные фото уже загружены в Supabase Storage в папку:

places

Имена файлов уже соответствуют:

image_tag

То есть для строки:

image_tag = moscow_1

реальное фото лежит как:

places/moscow_1.webp

Для СПб:

places/spb_1.webp
и т.д.
8.2. Как формировать storage_key для реального фото

Если у строки есть image_tag, нужно использовать:

storage_key = 'places/' || image_tag || '.webp'

Пример:

places/moscow_1.webp
places/spb_245.webp
8.3. Как записывать реальное фото в place_enrichment.photos

Если реальное фото существует в storage, то в photos должно быть:

8.4. Если реального фото нет

Если файл по image_tag не найден в storage, надо поставить category-placeholder.

Placeholder-путь:
categories/<type>/<N>.webp

Примеры:

categories/bar/3.webp
categories/restaurant/11.webp
categories/karaoke/4.webp
categories/hookah/2.webp
categories/bathhouse/7.webp
Правило выбора placeholder

Нужен рандомный, но детерминированный выбор:

не truly random на каждом прогоне
а стабильный выбор на основе place identity

Рекомендация:

брать hash(normalized_title + normalized_address)
по модулю количества файлов в папке категории выбирать индекс placeholder

Это даст:

визуально случайное распределение,
но повторный прогон не будет менять placeholder у уже обработанного места.
Запись в photos для placeholder
9. Новые типы мест

В новых таблицах появились дополнительные типы:

hookah
karaoke
bathhouse

Они должны быть полноценно поддержаны.

9.1. Нужно проверить наличие в app_place_categories

Если категорий ещё нет, добавить:

hookah
karaoke
bathhouse
9.2. Нужно убедиться, что для них есть category placeholders

В storage должны существовать:

categories/hookah/...
categories/karaoke/...
categories/bathhouse/...

Если папок или файлов нет — это обязательная подготовительная задача.

10. Слияние типов, если найден дубль по названию и адресу

Это ключевое правило.

Если при матчинге выясняется, что в БД уже есть место с таким же названием и адресом, но тип заведения отличается, то:

новое место не создаём
сливаем всё в одно место
итоговое множество типов = union(existing_types, imported_types)
Пример

В БД:

place = bar

В новом CSV:

то же место = bar,karaoke

Итог:

остаётся один place_id
типы места становятся:
bar
karaoke

Если в новом CSV:

bar,karaoke,hookah

А в БД было:

restaurant

И место матчится по title+address

Итог:

один place_id
итоговые типы:
restaurant
bar
karaoke
hookah
11. Как хранить несколько типов
11.1. Источник полной мультикатегорийности

Полный набор типов должен храниться в:

core_place_category_links
11.2. Что делать с core_places.category

Так как core_places.category — одиночное поле, нужен primary_category.

Правило:

Собрать итоговый набор типов:
все типы из matched place
все типы из CSV
Если текущий core_places.category уже входит в итоговый набор — оставить его, чтобы не делать лишний churn
Если не входит — взять primary category по приоритету:
restaurant
bar
nightclub
karaoke
hookah
bathhouse
cinema
theatre
11.3. Синхронизация links

После расчёта итогового набора типов:

удалить устаревшие links, которых больше нет
добавить отсутствующие links, которых не было
итог core_place_category_links должен строго совпадать с финальным набором типов
12. Что делать с новыми местами, которых ещё нет в БД

Если строка из CSV не матчится ни к одному existing place:

создать новый core_places
создать place_enrichment
создать core_place_category_links
поставить фото:
реальное по image_tag, если есть
иначе placeholder
12.1. Для новых мест обязательны
title
category / primary_category
lat
lng
address
area_id
12.2. area_id

Так как core_places.area_id not null, для новых мест нужен отдельный resolver.

Правило:

для Москвы и СПб при создании нового места должен быть определён корректный area_id
если resolver не может уверенно определить area — строку не вставлять автоматически, а отправлять в review queue
13. Идемпотентность

Процедура должна быть идемпотентной.

Это значит:

повторный запуск тех же CSV не должен плодить дубли
повторный запуск должен только:
подтверждать match
обновлять поля, если нужно
не создавать второй раз тот же core_places
не дублировать category links
не ломать photos
14. Приоритет источников данных

Для matched place источники по приоритету такие:

14.1. Для базовых данных места

CSV приоритетнее старых значений БД:

title
address
lat
lng
14.2. Для enrichment

CSV приоритетнее при условии, что значение не пустое:

website
phone
rating
14.3. Для фото

Приоритет:

Реальное фото по image_tag
Если real photo нет — placeholder из categories/<type>/...
14.4. Для типов

Итоговый набор типов = union(existing + incoming)

15. Ограничения и запреты

В этой процедуре нельзя:

менять структуру core_places
ломать текущий контракт чтения фото через place_enrichment.photos
писать фото по догадке без match
затирать непустые enrichment-поля пустыми значениями из CSV
создавать новый place, если есть уверенный existing match
автоматом сливать случаи с несколькими competing matches
16. Технический рекомендуемый пайплайн реализации
Этап 1. Загрузка входных CSV в staging

Создать временную/staging таблицу, например:

place_import_staging

Поля staging:

source_city
title
address
lat
lng
type
tag
rating
phone
website
image_tag
normalized_title
normalized_address
parsed_types
resolved_storage_key
matched_place_id
match_status
conflict_reason
Этап 2. Нормализация и предобработка
нормализовать title/address
распарсить type в массив
построить storage_key = places/<image_tag>.webp
Этап 3. Матчинг к существующим местам
искать existing place по normalized title + normalized address
фиксировать matched_place_id
ambiguous cases → conflict
Этап 4. Update existing

Для matched rows:

update core_places
upsert place_enrichment
sync core_place_category_links
update photos
Этап 5. Insert new

Для unmatched rows:

определить area_id
insert core_places
insert place_enrichment
insert category links
записать фото
Этап 6. Review report

На выходе нужен отчёт:

matched updated count
newly inserted count
conflict/manual review count
real photo attached count
placeholder assigned count
places with merged additional categories count
17. Проверки после выполнения

После процедуры нужно обязательно проверить:

17.1. Фото
места с real photo имеют photos[0].is_placeholder = false
места без real photo имеют photos[0].is_placeholder = true
storage_key реально существует в storage
17.2. Типы
core_place_category_links содержит весь итоговый набор типов
новые типы hookah, karaoke, bathhouse корректно прописаны
17.3. Дубли
не появилось вторых core_places для уже существующих адресов/названий
при matched cases обновлён существующий place, а не создан новый
17.4. Клиент
get_place_details_meta_v1(place_id) возвращает корректное photos
place details отдают обновлённые enrichment-данные
18. Ожидаемый конечный результат

После выполнения процедуры должно быть так:

Все места из новых CSV либо:
сматчены к existing places,
либо вставлены как новые
У matched places:
обновлены базовые данные
обновлён enrichment
обновлены типы
привязано реальное фото или placeholder
У new places:
создан core_places
создан place_enrichment
созданы category links
привязано real photo / placeholder
Фото для клиента тянутся через:
place_enrichment.photos[].storage_key
При отсутствии real photo клиент получает не “нет фото”, а категорийный placeholder из:
categories/<type>/...