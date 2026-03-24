ТЗ для архитектора / кодера
Модуль: Support Center / Live Support Chat с маршрутизацией по типу обращения
1. Цель модуля

Реализовать в приложении блок поддержки, который при открытии сначала предлагает пользователю выбрать направление обращения:

Вопросы
Предложения
Жалобы

Далее логика расходится:

Вопросы
обрабатываются AI-контуром по базе знаний проекта (RAG: retrieval + generation).
Предложения
не обрабатываются AI, а сохраняются в отдельную таблицу и подтверждаются автоответом.
Жалобы
не обрабатываются AI, а сохраняются в отдельную таблицу и подтверждаются автоответом.
2. Принципы реализации
2.1. Server-first

Сервер — единственный источник истины.

Клиент:

не принимает бизнес-решений,
не решает, куда маршрутизировать запрос,
не формирует канонические тексты системных ответов,
не содержит ключей внешних AI-сервисов,
не ходит напрямую в AI API.

Сервер:

создаёт сессии поддержки,
определяет сценарий обработки,
формирует ответы,
логирует обращения,
хранит и ищет контекст базы знаний,
вызывает внешнюю AI-модель,
возвращает клиенту готовый payload для рендера.
2.2. Разделение сценариев

Нельзя смешивать AI-вопросы и офлайн-обращения в одну “универсальную” таблицу сообщений без необходимости.

Должны быть отдельно:

сущность сессии обращения,
сущность сообщений AI-чата,
таблица предложений,
таблица жалоб.
2.3. Россия / без VPN для пользователя

Обязательное требование:

пользовательский клиент работает через обычный backend/API проекта;
никакие внешние AI SDK/ключи на клиент не выносятся;
AI провайдер доступен только серверу;
при временной недоступности AI-провайдера приложение не ломается: сервер возвращает контролируемый fallback-ответ.
3. Пользовательские сценарии
3.1. Сценарий входа в поддержку

Когда пользователь открывает раздел поддержки, он сначала видит экран выбора направления:

Вопросы
Предложения
Жалобы

До выбора направления обычный чат не открывается.

3.2. Сценарий “Вопросы”
Пользователь выбирает “Вопросы”.
Создаётся support session типа QUESTION.
Открывается экран диалога.
Пользователь отправляет сообщение.
Сервер:
сохраняет вопрос,
ищет релевантные фрагменты базы знаний,
формирует prompt,
вызывает AI,
получает ответ,
сохраняет ответ,
возвращает ответ клиенту.
Клиент просто отображает:
сообщение пользователя,
ответ ассистента,
при необходимости системные статусы.
Правила ответа

AI должен отвечать:

только в рамках найденного контекста и известных материалов,
без фантазий,
без выдумывания политик, функционала или правил приложения,
кратко и по делу,
на языке пользователя.

Если точный ответ не найден:

AI не выдумывает,
сервер возвращает канонический fallback-ответ, например:
“Не удалось найти точный ответ по вашему вопросу. Попробуйте уточнить формулировку.”
опционально можно предложить повторную формулировку.
3.3. Сценарий “Предложения”
Пользователь выбирает “Предложения”.
Создаётся support session типа SUGGESTION.
Открывается экран формы с полем ввода.
Пользователь вводит текст предложения.
После отправки сервер:
сохраняет предложение в отдельную таблицу,
помечает сессию как обработанную,
возвращает канонический системный ответ.

Пример ответа:

“Спасибо, ваше предложение принято и будет рассмотрено.”

Полноценный AI-чат в этом сценарии не нужен.

3.4. Сценарий “Жалобы”
Пользователь выбирает “Жалобы”.
Создаётся support session типа COMPLAINT.
Открывается экран формы с полем ввода.
Пользователь вводит текст жалобы.
После отправки сервер:
сохраняет жалобу в отдельную таблицу,
помечает сессию как обработанную,
возвращает канонический системный ответ.

Пример ответа:

“Спасибо, ваша жалоба принята в обработку.”

Полноценный AI-чат в этом сценарии не нужен.

4. MVP-границы

В MVP обязательно:

выбор направления при входе,
AI-чат только для “Вопросов”,
отдельные таблицы для жалоб и предложений,
автоответ для жалоб и предложений,
база знаний с семантическим поиском,
логирование вопросов и AI-ответов,
fallback при недоступности AI,
экспорт жалоб и предложений.

В MVP не обязательно:

живой оператор,
CRM,
тикетная система,
вложения,
аудио/голос,
мультиязычный backoffice,
приоритизация жалоб,
ML-классификация обращений.
5. Архитектура решения
5.1. Базовый стек

Рекомендуемая базовая архитектура:

Supabase Postgres
pgvector для векторного поиска по базе знаний
Supabase Edge Functions как серверный orchestration layer
внешний AI provider для генерации ответа
Flutter client как тупой UI

Supabase Edge Functions — это server-side TypeScript/Deno-функции; Supabase отдельно поддерживает pgvector и AI/Vector сценарии, включая автоматизацию embeddings через Edge Functions, очереди и cron. Edge Function invocations тарифицируются отдельно: $2 за 1 млн вызовов сверх квоты, с квотой 500k на Free и 2 млн на Pro. Ограничения функции: 256 MB памяти, CPU time 2s, wall-clock 150s на Free и 400s на paid; это подходит для тонкой orchestration-логики, но не для тяжёлой синхронной обработки внутри запроса.

5.2. Почему не выносить это в клиент

Запрещено:

класть AI API key в Flutter,
делать прямые запросы из приложения в Groq/OpenRouter/Cloudflare/DeepSeek,
позволять клиенту самому выбирать модель/провайдера.

Причина:

безопасность,
контроль расходов,
контроль rate limits,
возможность замены провайдера без обновления приложения,
выполнение требования “работает в России без VPN для пользователя”.
5.3. Почему не делать Cloudflare Workers AI первым контуром

Cloudflare Workers AI возможен как альтернативный контур, но на старте не обязателен. У Workers AI своё отдельное ценообразование по neurons, а Workers Paid имеет минимальный платёж $5/месяц. Это нормальный вариант, но он создаёт второй операционный контур поверх Supabase. Для данного модуля предпочтительнее сначала собрать всё внутри текущего server-first стека на Supabase + внешний AI provider.

6. Модель данных
6.1. support_sessions

Общая сущность обращения.

Поля:

id uuid pk
app_user_id uuid not null
direction text not null
значения: QUESTION | SUGGESTION | COMPLAINT
status text not null
значения: OPEN | CLOSED | ESCALATED | FAILED
created_at timestamptz not null
updated_at timestamptz not null
last_message_at timestamptz null
metadata jsonb null

Индексы:

(app_user_id, created_at desc)
(direction, status, created_at desc)
6.2. support_question_messages

Только для сценария “Вопросы”.

Поля:

id uuid pk
session_id uuid not null fk -> support_sessions.id
app_user_id uuid not null
sender_type text not null
значения: USER | ASSISTANT | SYSTEM
message_text text not null
answer_status text null
значения: OK | NO_ANSWER | FALLBACK | ERROR
sources_json jsonb null
model_name text null
provider_name text null
tokens_input int null
tokens_output int null
latency_ms int null
created_at timestamptz not null

Индексы:

(session_id, created_at asc)
(app_user_id, created_at desc)
6.3. support_suggestions

Отдельная таблица предложений.

Поля:

id uuid pk
session_id uuid not null fk -> support_sessions.id
app_user_id uuid not null
text text not null
status text not null
значения: NEW | REVIEWED | ACCEPTED | REJECTED
admin_comment text null
created_at timestamptz not null
updated_at timestamptz not null

Индексы:

(status, created_at desc)
(app_user_id, created_at desc)
6.4. support_complaints

Отдельная таблица жалоб.

Поля:

id uuid pk
session_id uuid not null fk -> support_sessions.id
app_user_id uuid not null
text text not null
status text not null
значения: NEW | IN_REVIEW | RESOLVED | REJECTED
admin_comment text null
created_at timestamptz not null
updated_at timestamptz not null

Индексы:

(status, created_at desc)
(app_user_id, created_at desc)
6.5. kb_documents

Документы базы знаний.

Поля:

id uuid pk
slug text unique not null
title text not null
source_type text not null
значения: MANUAL | FAQ | POLICY | GUIDE | FEATURE_DOC
status text not null
значения: DRAFT | PUBLISHED | ARCHIVED
language_code text not null default 'ru'
created_at timestamptz not null
updated_at timestamptz not null
6.6. kb_document_versions

Версионирование контента БЗ.

Поля:

id uuid pk
document_id uuid not null fk -> kb_documents.id
version_no int not null
content_markdown text not null
published_at timestamptz null
created_at timestamptz not null
is_active boolean not null

Индекс:

(document_id, version_no desc)
6.7. kb_chunks

Нарезанные фрагменты для поиска.

Поля:

id uuid pk
document_id uuid not null
document_version_id uuid not null
chunk_no int not null
chunk_text text not null
token_count int null
embedding vector(...) not null
metadata jsonb null
created_at timestamptz not null

Индексы:

ivfflat/hnsw по embedding
(document_id, document_version_id, chunk_no)
6.8. support_answer_feedback

Обратная связь на AI-ответ.

Поля:

id uuid pk
message_id uuid not null fk -> support_question_messages.id
app_user_id uuid not null
feedback text not null
значения: UP | DOWN
comment text null
created_at timestamptz not null

Это желательно, но можно отложить на этап 2.

7. База знаний
7.1. Источники БЗ

В БЗ должны попадать только подготовленные и утверждённые материалы, например:

FAQ по приложению,
правила и ограничения,
описание функционала,
инструкции пользователя,
политика модерации,
объяснение сценариев приложения,
справка по разделам.

Не использовать для MVP:

“сырые” логи,
случайные тексты из чатов,
пользовательский контент без модерации,
неструктурированные дампы.
7.2. Формат хранения

Первичный контент хранить в БД как versioned markdown/text.

7.3. Индексация

Контент режется на chunks.

Рекомендации:

chunk size: примерно 600–1000 токенов
overlap: 80–120 токенов
хранить version_id, chunk_no, title, slug
7.4. Обновление embeddings

Embeddings не считать на каждом пользовательском вопросе.

Должен быть отдельный ingestion pipeline:

документ создан/обновлён,
создаётся/обновляется версия,
ставится задача на перерасчёт embeddings,
старые chunks деактивируются/заменяются.

Supabase отдельно показывает автоматизацию embeddings через Edge Functions, очереди, pg_net и pg_cron; этот подход допустим как референс для реализации pipeline.

8. Контур AI-ответа
8.1. Алгоритм ответа

Для каждого сообщения в сценарии “Вопросы”:

Получить session_id, app_user_id, message.
Проверить доступ пользователя к сессии.
Сохранить пользовательское сообщение.
Выполнить retrieval по БЗ:
semantic search по embeddings,
при необходимости hybrid search.
Отобрать top-K релевантных chunks.
Собрать system prompt:
отвечать только в рамках контекста,
не фантазировать,
если ответа нет — признать это,
отвечать по-русски.
Отправить запрос в LLM.
Сохранить AI-ответ вместе с metadata.
Вернуть клиенту ответ.
8.2. Запрещённое поведение AI

AI не должен:

выдумывать функции, которых нет,
придумывать решения модерации,
придумывать статусы заказа/жалобы,
выдавать юридические обещания,
ссылаться на несуществующие документы,
“уверенно врать” при отсутствии контекста.
8.3. Fallback

Если retrieval пустой или LLM не вернул валидный ответ:

вернуть канонический системный ответ,
пометить сообщение как NO_ANSWER или ERROR,
не показывать технический stack trace пользователю.
9. Серверные контракты

Ниже контракты на уровне backend API / RPC / Edge Function.

9.1. create_support_session_v1
Вход
direction
Выход
session_id
direction
status
initial_payload
Правила
создаёт support_sessions
возвращает стартовое состояние
9.2. get_support_session_v1
Вход
session_id
Выход
session metadata
messages/form state/history
9.3. send_support_question_message_v1
Вход
session_id
message_text
Выход
user_message
assistant_message
answer_status
sources
session_status
Правила
только для direction = QUESTION
если сессия не принадлежит пользователю — отказ
если AI недоступен — fallback
9.4. submit_support_suggestion_v1
Вход
session_id
text
Выход
status
system_message
Правила
только для direction = SUGGESTION
создаёт запись в support_suggestions
переводит сессию в CLOSED
9.5. submit_support_complaint_v1
Вход
session_id
text
Выход
status
system_message
Правила
только для direction = COMPLAINT
создаёт запись в support_complaints
переводит сессию в CLOSED
9.6. list_support_user_sessions_v1
Вход
опциональные фильтры
Выход
список обращений пользователя

Для MVP можно не выводить историю, но API лучше заложить сразу.

10. Клиентская реализация Flutter
10.1. Экран 1 — выбор направления

Показывает 3 варианта:

Вопросы
Предложения
Жалобы

По выбору вызывает create_support_session_v1.

10.2. Экран “Вопросы”

Показывает:

список сообщений,
поле ввода,
индикатор загрузки ответа,
системные fallback-сообщения.
10.3. Экран “Предложения”

Показывает:

поле ввода,
кнопку отправки,
после отправки — подтверждение.
10.4. Экран “Жалобы”

Показывает:

поле ввода,
кнопку отправки,
после отправки — подтверждение.
10.5. Правила клиента

Клиент:

не должен содержать AI-логики,
не должен выбирать model/provider,
не должен самостоятельно собирать историю для prompt,
только рендерит то, что вернул сервер.
11. Безопасность и доступ
11.1. RLS

Нужны политики, чтобы пользователь видел только:

свои support_sessions,
свои support_question_messages,
свои support_suggestions,
свои support_complaints.
11.2. Сервисные роли

Вызов внешнего AI и работа с KB ingestion идут только в доверенном серверном контуре.

11.3. Секреты

Все ключи внешних AI-провайдеров:

только в server-side secrets / environment variables,
не в клиенте,
не в репозитории.

Groq и OpenRouter работают через API keys; Groq в quickstart прямо рекомендует держать ключ в environment variable.

11.4. Rate limiting

Нужен rate limit минимум на:

создание новых question messages,
спам по жалобам/предложениям.

У Supabase есть пример rate limiting для Edge Functions.

12. Логи и аналитика

Нужно логировать:

число открытий support center,
выбранное направление,
число question sessions,
число suggestions,
число complaints,
число успешных AI-ответов,
число fallback-ответов,
число ошибок провайдера,
latency по AI-ответам,
средний размер input/output,
feedback up/down.
13. Экспорт и backoffice
13.1. Предложения

Должна быть возможность выгружать:

id
user id
text
status
created_at
13.2. Жалобы

Должна быть возможность выгружать:

id
user id
text
status
created_at

Формат:

SQL view
CSV export
либо admin query preset
13.3. База знаний

Нужен простой контур управления:

создать документ,
создать новую версию,
опубликовать,
переиндексировать.

Для MVP можно без красивой админки: достаточно SQL + внутреннего admin screen later.

14. Провайдер AI: целевая стратегия
14.1. Требование к архитектуре

Нужно сделать provider abstraction:

AiProvider
EmbeddingProvider

Чтобы без переписывания бизнес-логики можно было переключать:

OpenRouter
Groq
Cloudflare Workers AI
другой провайдер позже
14.2. Рекомендуемый стартовый вариант

Для твоего кейса я бы закладывал так:

Вариант по умолчанию

Supabase + OpenRouter

Почему:

pay-as-you-go,
нет minimum spend,
нет lock-in,
много моделей,
есть бесплатные варианты для теста,
оплата гибче: cards / crypto / bank transfers, а в FAQ отдельно указаны major cards, AliPay и USDC.
Практичная модель для старта

meta-llama/llama-3.1-8b-instruct
Цена: $0.02 / 1M input и $0.05 / 1M output.

Embeddings через OpenRouter

OpenRouter даёт OpenAI-compatible embeddings API. В качестве практичного стартового варианта можно взять, например, mistralai/mistral-embed-2312 по $0.10 / 1M input или openai/text-embedding-3-large по $0.13 / 1M input.

14.3. Альтернатива, если есть удобный международный биллинг

Groq как чат-провайдер:

llama-3.1-8b-instant
$0.05 / 1M input
$0.08 / 1M output
OpenAI-compatible API
ключ в env
поддержка кредиток, US bank, SEPA debit.
14.4. Что не делать

Не привязывать бизнес-логику к одному провайдеру жёстко.

15. Требования к отказоустойчивости

При любой ошибке AI/provider:

приложение не должно падать,
UI не должен зависать бесконечно,
пользователю отдаётся аккуратный fallback,
ошибка логируется на сервере.

При ошибке БЗ:

должен быть системный ответ о временной недоступности.
16. Требования к производительности
Вопросы должны обрабатываться в одном server round-trip сценарии.
Embeddings на документы — только асинхронно.
Никакой тяжёлой синхронной переиндексации внутри пользовательского запроса.
История чата грузится пагинацией.
В retrieval не передавать в prompt слишком много чанков.
17. Acceptance criteria

Считать задачу выполненной, если:

При входе в поддержку пользователь сначала видит выбор:
Вопросы
Предложения
Жалобы
При выборе “Вопросы”:
создаётся question session,
можно отправить вопрос,
сервер отвечает по БЗ,
ответ сохраняется,
клиент его отображает.
При выборе “Предложения”:
создаётся suggestion session,
предложение сохраняется в отдельную таблицу,
пользователь получает подтверждение.
При выборе “Жалобы”:
создаётся complaint session,
жалоба сохраняется в отдельную таблицу,
пользователь получает подтверждение.
При ошибке AI:
пользователь получает fallback,
приложение не ломается.
Пользователь не может получить чужие обращения.
Ключи AI-провайдера отсутствуют в клиенте.
Есть возможность выгрузить жалобы и предложения.
18. Deliverables от кодера / архитектора

Ожидаемый результат работы:

SQL migrations:
все таблицы
индексы
RLS policies
views/export helpers
Edge Functions / backend handlers:
create session
send question
submit suggestion
submit complaint
kb ingest / reindex hooks
Provider adapter layer:
OpenRouter adapter
опционально Groq adapter
Flutter UI:
экран выбора направления
question chat screen
suggestion form screen
complaint form screen
Конфигурация:
env vars
secrets
README по запуску
список required keys
Тест-кейсы:
happy path
provider down
no answer
spam/rate limit
unauthorized access



ДОПОЛНИТЕЛЬНО СООБЩАЮ:
OpenRouter API key - готов предоставить по запросу
База знаний находится в BZ.md
Правила поведения оператора в чате в Pravila_chat.md 
Можешь их использовать и загружать.