# Перенос centry.website с Vercel на VPS в РФ

Цель: починить magic link и invite-ссылки в РФ без релиза клиента.
Тот же приём, что в TZ10 для api: только теперь не подменяем домен, а
переключаем DNS уже существующего `centry.website` на тот же VPS.

VPS: `147.45.185.143` (Timeweb SPB), там же уже работает `api.centryweb.ru`.

---

## Шаг 1. На локальной машине — собрать статику

```bash
cd /Users/jcat/Documents/Doc/centry-flutter
./ops/centry-website-proxy/build_static.sh
```

Получишь готовый каталог `ops/centry-website-proxy/dist/` со всем,
что должно лежать на VPS:

* Flutter Web build лендинга (index.html, main.dart.js, иконки и т.п.)
* `auth-callback.html` (magic link redirect → centry://auth)
* `invite.html` + `plan-invite/index.html`
* `apple-app-site-association` в двух местах: `/.well-known/` и в корне
* лого `appstore-logo.svg`, `googleplay-logo.svg`, `rustore-logo.svg`,
  `centry_logo.png`

---

## Шаг 2. На VPS — подготовить структуру

SSH:
```bash
ssh root@147.45.185.143
```

Создать директории и убедиться, что nginx + certbot стоят:
```bash
mkdir -p /var/www/centry.website
mkdir -p /var/www/certbot
apt-get update && apt-get install -y nginx certbot python3-certbot-nginx
```

---

## Шаг 3. Залить статику с локальной машины

С локальной машины (НЕ с VPS):
```bash
rsync -avz --delete \
  /Users/jcat/Documents/Doc/centry-flutter/ops/centry-website-proxy/dist/ \
  root@147.45.185.143:/var/www/centry.website/
```

---

## Шаг 4. Положить nginx-конфиг

С локальной машины:
```bash
scp /Users/jcat/Documents/Doc/centry-flutter/ops/centry-website-proxy/centry.website.nginx.conf \
  root@147.45.185.143:/etc/nginx/sites-available/centry.website
```

На VPS:
```bash
ln -sf /etc/nginx/sites-available/centry.website /etc/nginx/sites-enabled/centry.website
```

⚠ **Сначала ssl-сертификат, потом enable.** Чтобы nginx не упал на старте
из-за отсутствующих файлов сертификата, временно закомментируй в конфиге
блоки `listen 443 ssl` (или удали символическую ссылку до получения
сертификата) и оставь только `listen 80` блок. Получи сертификат, потом
раскомментируй обратно.

Альтернатива — выпустить сертификат через standalone, не трогая nginx:

```bash
systemctl stop nginx
certbot certonly --standalone -d centry.website -d www.centry.website \
  --agree-tos -m carbon.arma3@gmail.com --non-interactive
systemctl start nginx
```

После получения сертификата:
```bash
nginx -t  # проверка синтаксиса
systemctl reload nginx
```

---

## Шаг 5. Проверка ДО переключения DNS (через --resolve)

Самое важное — **проверить, что VPS отдаёт всё правильно, ДО того
как переключим DNS**. Иначе у пользователей моментально отвалится
magic link и инвайты на время отладки.

С любого устройства:
```bash
# Лендинг
curl -I --resolve www.centry.website:443:147.45.185.143 https://www.centry.website/

# Magic link callback
curl -i --resolve www.centry.website:443:147.45.185.143 https://www.centry.website/auth-callback

# Invite
curl -i --resolve www.centry.website:443:147.45.185.143 https://www.centry.website/plan-invite

# Apple App Site Association — должно быть Content-Type: application/json
curl -i --resolve www.centry.website:443:147.45.185.143 \
  https://www.centry.website/.well-known/apple-app-site-association
```

Что должно быть в ответах:
* всё — `HTTP/2 200`
* AASA — `content-type: application/json` и валидный JSON
* `auth-callback` — содержит `centry://auth`
* `plan-invite` — содержит `centry://plan-invite`

Можно для большей уверенности добавить временную запись в `/etc/hosts`
на одном телефоне и руками открыть свою же magic-link ссылку (имитация
будущей реальности).

---

## Шаг 6. Переключение DNS

В reg.ru (или там, где у тебя зона `centry.website`):

| Тип | Имя              | Значение         |
|-----|------------------|------------------|
| A   | `@` (centry.website)     | `147.45.185.143` |
| A   | `www`            | `147.45.185.143` |

Vercel-овские записи (CNAME на `cname.vercel-dns.com` или их IP) — удалить.

TTL рекомендую заранее снизить до 300 секунд за пару часов до
переключения, чтобы быстрее распространилось.

---

## Шаг 7. Проверка ПОСЛЕ переключения DNS

Подожди 5–15 мин (DNS propagation), потом:

```bash
dig +short www.centry.website     # должно быть 147.45.185.143
dig +short centry.website         # должно быть 147.45.185.143

curl -I https://www.centry.website/
curl -i https://www.centry.website/auth-callback
curl -i https://www.centry.website/.well-known/apple-app-site-association
```

Реальная проверка с устройства в РФ **без VPN**:
1. Магик-линк: запрос на email на тестовый аккаунт → клик в письме → должно
   открыться приложение через `centry://auth`.
2. Инвайт: создать план, расшарить ссылку, открыть в браузере мобилки →
   должна открыться страница `invite.html`, кнопка ведёт в приложение.
3. Если приложение не установлено — должны показываться кнопки сторов.

---

## Шаг 8. Vercel

Только после того как всё проверено в проде:
* В Vercel-проекте отключи Custom Domain `centry.website` и `www.centry.website`
  (project settings → Domains → Remove).
* Сам деплой можно оставить (на vercel.app поддомене), либо
  заархивировать. Но домен с него снять обязательно — иначе Vercel может
  начать выдавать 404 / редиректы по своему усмотрению, если кто-то
  попадёт туда напрямую.

---

## Откат (если что-то пойдёт не так)

Просто верни DNS-записи на Vercel-овские IP/CNAME. TTL низкий —
откатится за минуты. Всё, что ты делал на VPS, при этом не мешает.

---

## Что НЕ трогаем

* Клиент Flutter (`lib/`) — ноль изменений.
* Supabase Auth (Site URL, Redirect URLs) — ноль изменений.
* Релизы в Google Play / RuStore / App Store — НЕ нужны.
* `api.centryweb.ru` — продолжает работать как работал.

---

## Чек-лист на бумажку

* [ ] `build_static.sh` локально → есть `dist/`
* [ ] VPS: nginx + certbot установлены
* [ ] статика залита в `/var/www/centry.website/`
* [ ] сертификат Let's Encrypt получен на оба хоста
* [ ] nginx-конфиг включён, `nginx -t` ok, `systemctl reload nginx`
* [ ] curl с `--resolve` возвращает 200 для `/`, `/auth-callback`, `/plan-invite`
* [ ] AASA отдаётся как `application/json`
* [ ] DNS A-записи переключены на 147.45.185.143
* [ ] DNS пропагирован, реальный curl возвращает 200
* [ ] magic link на email → клик с устройства в РФ без VPN → открывает приложение
* [ ] invite на план → клик с устройства в РФ без VPN → открывает приложение
* [ ] Vercel — домен отвязан
