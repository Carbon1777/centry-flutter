# ТЗ: Видео-интро в онбординге

## Цель
Встроить 10-минутное видео (intro.mp4, 70 МБ, вертикальное 1080x1920) как часть онбординга приложения. Видео показывается один раз при первом запуске, перед экраном ввода никнейма. По окончании видео — автоматический переход к NicknameScreen. Есть кнопка "Пропустить".

## Где лежит видео
- Supabase Storage, бакет `brand-media` (публичный, лимит 100 МБ)
- URL: `https://lqgzvolirohuettizkhx.supabase.co/storage/v1/object/public/brand-media/intro.mp4`
- Там же лежит `player.html` — HTML-обёртка для WebView-подхода (можно удалить если не понадобится)

## Что уже сделано (файлы в проекте)

### 1. Экран видео-интро
- **Файл:** `lib/features/onboarding/intro_video_screen.dart`
- StatefulWidget с `onDone` callback
- Статические методы `shouldShow()` / `markSeen()` через SharedPreferences (ключ `intro_video_seen`)
- Кнопка "Пропустить" — внизу по центру, серый текст (alpha 0.45), `bottom: padding + 40`

### 2. Навигация в app.dart
- **Файл:** `lib/app/app.dart`
- Импорт: `import '../features/onboarding/intro_video_screen.dart';`
- Добавлен флаг `bool _showIntroVideo = false;`
- В `_restore()` → секция ONBOARDING: `final showVideo = await IntroVideoScreen.shouldShow();` + `_showIntroVideo = showVideo;`
- В `build()` перед `NicknameScreen`: если `_showIntroVideo` — показывает `IntroVideoScreen`, по `onDone` — `setState(() => _showIntroVideo = false)`

### 3. Пакеты в pubspec.yaml
- `webview_flutter` — добавлен (текущий подход)
- `video_player` — УДАЛЁН (вызывал проблемы)
- `flutter_widget_from_html_core` — добавлен (для юридических документов, не связан с видео)

## Что НЕ сработало и почему

### Подход 1: video_player (нативный плеер Flutter)
- **Пакет:** `video_player` (официальный, использует ExoPlayer на Android)
- **Проблема:** На двух устройствах Xiaomi приложение вообще не запускалось — вечный спиннер загрузки. На iPhone и Google Pixel — работало нормально
- **Вероятная причина:** Плагин `video_player` при регистрации нативных компонентов крашит/зависает на некоторых Xiaomi с MIUI. Crash происходит на уровне инициализации Flutter engine, до нашего кода
- **Попытки исправления:** Добавлен таймаут 15 сек на initialize() — не помогло, т.к. проблема была до создания экрана
- **Вывод:** Если пробовать снова — нужен ЧИСТЫЙ билд (`flutter clean && flutter pub get`). Возможно проблема была в кэше нативного билда после добавления плагина. Стоит попробовать ещё раз с чистым билдом

### Подход 2: url_launcher (системный плеер)
- **Пакет:** `url_launcher` (уже есть в проекте)
- **Проблема:** Видео открывается в отдельном системном плеере. Это НЕ часть онбординга — пользователь смотрит видео, оно заканчивается, и ничего не происходит. Нет автоперехода к следующему шагу
- **Вывод:** Не подходит концептуально. Видео должно быть частью flow, а не внешней штукой

### Подход 3: webview_flutter (WebView с HTML-плеером)
- **Пакет:** `webview_flutter`
- **Попытка 3а:** `loadHtmlString()` с встроенным `<video>` тегом
  - Чёрный экран. Причина: origin `about:blank` блокирует загрузку внешних ресурсов (видео с Supabase)
- **Попытка 3б:** `loadRequest()` с URL на `player.html` (залит в Supabase Storage)
  - Чёрный экран на Xiaomi. WebView грузится (видно по логам chromium), но видео не воспроизводится
  - Логи: `FrameEvents: updateAcquireFence: Did not find frame` — повторяется многократно
  - На этом остановились

## Рекомендации для следующей сессии

### Вариант А: Повторить video_player с чистым билдом
1. `flutter clean && flutter pub get`
2. Удалить приложение с Xiaomi
3. Собрать заново и установить
4. Если заработает — это был кэш нативного билда. Это самый чистый вариант

### Вариант Б: media_kit (альтернативный видеоплеер)
- Пакет `media_kit` + `media_kit_video` — использует mpv/libmpv вместо ExoPlayer
- Может работать лучше на Xiaomi т.к. не зависит от системных кодеков
- Минус: тяжелее чем video_player

### Вариант В: WebView с доработкой
- Попробовать `setMediaPlaybackRequiresUserGesture(false)` через platform-specific Android API
- Нужен `webview_flutter_android` как прямая зависимость
- Или: не autoplay, а показать кнопку "Играть" поверх WebView, по нажатию — runJavaScript('document.getElementById("v").play()')

### Вариант Г: Чистый нативный подход
- Написать platform channel который вызывает нативный Android MediaPlayer / iOS AVPlayer
- Максимальная совместимость, но больше кода

## Контекст: что ещё сделано в этой сессии (не связано с видео)

1. **HTML-рендеринг юридических документов** — `legal_document_screen.dart`: заменён `SelectableText` на `HtmlWidget` (пакет `flutter_widget_from_html_core`). Документы хранятся в HTML на сервере, теперь рендерятся нормально
2. **Заголовки экранов слева** — `app_theme.dart`: добавлен `centerTitle: false` в глобальную AppBarTheme
3. **Лендинг: один видеоплеер** — `landing/index.html` + `landing/css/style.css`: секция с 10 видео-плейсхолдерами заменена на один мокап телефона с `<video>` плеером. Задеплоено на GitHub Pages
4. **Коммит-якорь:** тег `ждем-аппл` на коммите `38d8c5e`
