#!/usr/bin/env node
/**
 * Скрипт обогащения мест Centry через Яндекс.Карты (Playwright).
 *
 * Использование:
 *   node scripts/yandex_enrich.js                        # все необогащённые
 *   node scripts/yandex_enrich.js --city "Казань"        # конкретный город
 *   node scripts/yandex_enrich.js --limit 50             # лимит
 *   node scripts/yandex_enrich.js --category "restaurant"
 *   node scripts/yandex_enrich.js --placeholders-only    # только заглушки фото
 */
import { chromium } from 'playwright';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import https from 'https';
import http from 'http';
import { fileURLToPath } from 'url';
import { config } from 'dotenv';

// ── Config ──────────────────────────────────────────────
const __filename2 = fileURLToPath(import.meta.url);
config({ path: path.join(path.dirname(__filename2), '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY;
const PROVIDER = 'yandex_maps';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PHOTOS_DIR = path.join(__dirname, '..', 'scraped_photos');
const LOGS_DIR = path.join(__dirname, '..', 'logs');

// ── CLI args ────────────────────────────────────────────
function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { city: null, limit: null, category: null, placeholdersOnly: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--city' && args[i + 1]) opts.city = args[++i];
    else if (args[i] === '--limit' && args[i + 1]) opts.limit = parseInt(args[++i], 10);
    else if (args[i] === '--category' && args[i + 1]) opts.category = args[++i];
    else if (args[i] === '--placeholders-only') opts.placeholdersOnly = true;
  }
  return opts;
}

// ── Supabase REST helpers ───────────────────────────────
async function withRetry(fn, retries = 3, delayMs = 5000) {
  for (let i = 0; i < retries; i++) {
    try { return await fn(); }
    catch (err) {
      if (i < retries - 1) {
        log(`  ⚠ Сеть: ${err.message}. Повтор через ${delayMs / 1000}с (${i + 1}/${retries})...`);
        await new Promise(r => setTimeout(r, delayMs));
      } else { throw err; }
    }
  }
}

function sbFetchOnce(pathStr) {
  return new Promise((resolve, reject) => {
    const url = new URL(pathStr, SUPABASE_URL);
    const req = https.request(url, {
      method: 'GET',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch { reject(new Error(`Parse error: ${data.slice(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    req.end();
  });
}

function sbFetch(pathStr) {
  return withRetry(() => sbFetchOnce(pathStr));
}

function sbPostOnce(pathStr, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(pathStr, SUPABASE_URL);
    const payload = JSON.stringify(body);
    const req = https.request(url, {
      method: 'POST',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
      },
    }, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => resolve(res.statusCode));
    });
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function sbPost(pathStr, body) {
  return withRetry(() => sbPostOnce(pathStr, body));
}

// ── Fetch places to enrich ──────────────────────────────
async function getPlacesToEnrich(opts) {
  // 1. Получаем place_id, которые уже обработаны yandex_maps
  const alreadyDone = new Set();
  let offset = 0;
  while (true) {
    const batch = await sbFetch(
      `/rest/v1/place_search_results_raw?select=place_id&provider=eq.${PROVIDER}&limit=1000&offset=${offset}`
    );
    for (const r of batch) alreadyDone.add(r.place_id);
    if (batch.length < 1000) break;
    offset += 1000;
  }
  log(`Уже обработано yandex_maps: ${alreadyDone.size}`);

  // 2. Получаем area → city маппинг
  const areas = await sbFetch('/rest/v1/core_areas?select=id,name,city:core_cities(name)');
  const areaMap = {};
  for (const a of areas) {
    areaMap[a.id] = a.city?.name || '';
  }

  // 3. Если --placeholders-only, получаем place_id с заглушками
  let placeholderIds = null;
  if (opts.placeholdersOnly) {
    placeholderIds = new Set();
    let off = 0;
    while (true) {
      const batch = await sbFetch(
        `/rest/v1/place_enrichment?select=place_id,photos&limit=1000&offset=${off}`
      );
      for (const r of batch) {
        const photos = r.photos;
        if (Array.isArray(photos) && photos.length > 0 && photos[0].is_placeholder === true) {
          placeholderIds.add(r.place_id);
        }
      }
      if (batch.length < 1000) break;
      off += 1000;
    }
    log(`Мест с заглушками: ${placeholderIds.size}`);
  }

  // 4. Загружаем все места порциями
  const allPlaces = [];
  offset = 0;
  while (true) {
    const batch = await sbFetch(
      `/rest/v1/core_places?select=id,title,category,address,lat,lng,area_id&order=title&limit=1000&offset=${offset}`
    );
    if (!batch.length) break;
    allPlaces.push(...batch);
    if (batch.length < 1000) break;
    offset += 1000;
  }
  log(`Всего мест в core_places: ${allPlaces.length}`);

  // 5. Фильтрация
  const filtered = allPlaces.filter((p) => {
    if (alreadyDone.has(p.id)) return false;
    if (opts.category && p.category !== opts.category) return false;
    if (opts.placeholdersOnly && placeholderIds && !placeholderIds.has(p.id)) return false;
    const city = areaMap[p.area_id] || '';
    if (opts.city && city !== opts.city) return false;
    return true;
  });

  // Приоритет: региональные города первыми
  const priority = [];
  const secondary = [];
  for (const p of filtered) {
    const city = areaMap[p.area_id] || '';
    p._city = city;
    if (city === 'Москва' || city === 'Санкт-Петербург') {
      secondary.push(p);
    } else {
      priority.push(p);
    }
  }

  let result = [...priority, ...secondary];
  if (opts.limit) result = result.slice(0, opts.limit);

  // Распределение по городам
  const dist = {};
  for (const p of result) {
    dist[p._city || '?'] = (dist[p._city || '?'] || 0) + 1;
  }
  log(`К обогащению: ${result.length} мест`);
  log(`Распределение: ${JSON.stringify(dist)}`);

  return result;
}

// ── Playwright helpers ──────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitForCaptchaIfNeeded(page) {
  if (!page.url().includes('showcaptcha')) return;
  log('⚠ Captcha! Реши вручную в браузере...');
  while (page.url().includes('showcaptcha')) {
    await sleep(2000);
  }
  log('✓ Captcha solved');
  await sleep(3000);
}

async function searchPlace(page, title, city) {
  const query = `${title} ${city}`;
  const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(5000);
  await waitForCaptchaIfNeeded(page);
}

async function findFirstOrgLink(page) {
  // Ищем первую ссылку на организацию (/maps/org/...)
  const orgLinks = await page.$$('a[href*="/maps/org/"]');
  if (orgLinks.length === 0) return null;

  const href = await orgLinks[0].getAttribute('href');
  return href;
}

async function openOrgCard(page, href) {
  // Если href относительный — строим полный url
  const fullUrl = href.startsWith('http') ? href : `https://yandex.ru${href}`;
  await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(3000);
  await waitForCaptchaIfNeeded(page);
}

async function openOverviewTab(page) {
  // Пытаемся кликнуть вкладку «Обзор» / «О месте»
  try {
    const tabSelectors = [
      'a[href*="/inside"]',
      'div[class*="tabs"] a:first-child',
      '[data-tab="overview"]',
    ];
    for (const sel of tabSelectors) {
      const tab = await page.$(sel);
      if (tab) {
        await tab.click();
        await sleep(2000);
        return;
      }
    }
  } catch {
    // Не критично — может уже быть на обзоре
  }
}

async function scrollToContactsBlock(page) {
  // Скроллим контентную область карточки вниз чтобы загрузить контакты
  try {
    const scrollable = await page.$('.scroll__container, .business-card__content, [class*="scroll"]');
    if (scrollable) {
      for (let i = 0; i < 5; i++) {
        await scrollable.evaluate((el) => el.scrollBy(0, 400));
        await sleep(500);
      }
    }
  } catch {
    // fallback: скролл страницы
    await page.evaluate(() => window.scrollBy(0, 1500));
    await sleep(1000);
  }
}

async function clickShowPhoneIfExists(page) {
  try {
    const btn = await page.$('button:has-text("Показать телефон"), a:has-text("Показать телефон"), [class*="phone"] button');
    if (btn) {
      await btn.click();
      await sleep(1500);
    }
  } catch {
    // Иногда телефон уже виден
  }
}

async function extractCardData(page) {
  return page.evaluate(() => {
    const result = {};

    // Название — h1 заголовок карточки
    const titleEl = document.querySelector(
      '.orgpage-header-view__header, .card-title-view__title-link, h1'
    );
    result.yandex_title = titleEl?.textContent?.trim() || '';

    // Адрес
    const addressEl = document.querySelector(
      '.orgpage-header-view__address, .business-contacts-view__address-link'
    );
    result.yandex_address = addressEl?.textContent?.trim() || '';

    // Категория (под заголовком, рядом с рейтингом)
    const catEl = document.querySelector(
      '.orgpage-header-view__category, .business-header-view__category'
    );
    result.yandex_category = catEl?.textContent?.trim() || '';

    // Рейтинг — берём первый .business-rating-badge-view__rating-text в шапке карточки
    const ratingContainer = document.querySelector(
      '.orgpage-header-view__wrapper-rating .business-rating-badge-view__rating-text'
    );
    if (ratingContainer) {
      result.rating = parseFloat(ratingContainer.textContent.trim().replace(',', '.')) || null;
    } else {
      // fallback: любой первый rating-text
      const allRatings = document.querySelectorAll('.business-rating-badge-view__rating-text');
      for (const el of allRatings) {
        const t = el.textContent?.trim();
        if (t && /^\d/.test(t)) {
          result.rating = parseFloat(t.replace(',', '.')) || null;
          break;
        }
      }
      if (!result.rating) result.rating = null;
    }

    // Количество отзывов
    const reviewsEl = document.querySelector(
      '.business-header-rating-view__text, .business-summary-rating-badge-view__rating-count'
    );
    const reviewsText = reviewsEl?.textContent?.trim() || '';
    const reviewsMatch = reviewsText.match(/(\d[\d\s]*)/);
    result.rating_count = reviewsMatch
      ? parseInt(reviewsMatch[1].replace(/\s/g, ''), 10)
      : null;

    // Телефон — только чистый номер из orgpage-phones-view__phone-number
    const phoneEl = document.querySelector('.orgpage-phones-view__phone-number');
    result.phone = phoneEl?.textContent?.trim() || null;

    // Все телефоны — собираем через a[href^="tel:"] или orgpage
    const phoneEls = document.querySelectorAll(
      '.orgpage-phones-view__phone-number, a[href^="tel:"]'
    );
    const phones = [];
    const seenPhones = new Set();
    phoneEls.forEach((el) => {
      let ph = el.textContent?.trim();
      if (!ph || ph.length < 6) return;
      // Убираем "Показать телефон" и пр.
      ph = ph.replace(/Показать\s*телефон/gi, '').trim();
      if (ph && !seenPhones.has(ph)) {
        seenPhones.add(ph);
        phones.push(ph);
      }
    });
    result.phones_all = phones;
    if (!result.phone && phones.length > 0) result.phone = phones[0];

    // Сайт
    const siteEl = document.querySelector(
      '.business-urls-view__link'
    );
    result.website = siteEl?.textContent?.trim() || siteEl?.getAttribute('href') || null;

    // Часы работы / статус работы
    const statusEl = document.querySelector(
      '.business-working-status-view'
    );
    result.working_hours = statusEl?.textContent?.trim() || null;

    // URL карточки
    result.yandex_url = window.location.href;

    // Фото — собираем до 3 фото из carousel карточки (пропускаем логотип)
    const mediaImgs = document.querySelectorAll('.orgpage-media-view__media img.img-with-alt');
    const photoUrls = [];
    const seenUrls = new Set();
    for (const img of mediaImgs) {
      const src = img.src || '';
      const alt = (img.alt || '').toLowerCase();
      // Пропускаем логотипы, панорамы, мелочь
      if (alt.includes('логотип') || alt.includes('logo')) continue;
      if (src.includes('static-pano') || src.includes('yastatic.net')) continue;
      if (!src.includes('avatars.mds.yandex.net')) continue;
      if ((img.naturalWidth || 0) < 200) continue;
      if (seenUrls.has(src)) continue;
      seenUrls.add(src);
      photoUrls.push(src);
      if (photoUrls.length >= 3) break;
    }

    // Fallback: если в carousel ничего — ищем любые большие фото
    if (photoUrls.length === 0) {
      const allImgs = document.querySelectorAll('img.img-with-alt');
      for (const img of allImgs) {
        const src = img.src || '';
        const alt = (img.alt || '').toLowerCase();
        if (alt.includes('логотип') || alt.includes('logo')) continue;
        if (src.includes('static-pano') || src.includes('yastatic.net')) continue;
        if (!src.includes('avatars.mds.yandex.net')) continue;
        if ((img.naturalWidth || 0) < 200) continue;
        if (seenUrls.has(src)) continue;
        seenUrls.add(src);
        photoUrls.push(src);
        if (photoUrls.length >= 3) break;
      }
    }
    result.photo_urls = photoUrls;
    result.photo_url = photoUrls[0] || null;

    return result;
  });
}

// ── Photo download & resize ─────────────────────────────
function downloadFile(url) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    proto.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return downloadFile(res.headers.location).then(resolve, reject);
      }
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function downloadAndResizePhotos(photoUrls, placeId) {
  if (!photoUrls || photoUrls.length === 0) return { downloaded: 0, localPaths: [] };
  const localPaths = [];
  for (let i = 0; i < photoUrls.length; i++) {
    try {
      const buffer = await downloadFile(photoUrls[i]);
      const resized = await sharp(buffer)
        .resize(600, 320, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 82 })
        .toBuffer();

      // Суффикс: _1, _2, _3 (первое фото без суффикса для обратной совместимости)
      const suffix = i === 0 ? '' : `_${i + 1}`;
      const filename = `${placeId}${suffix}.webp`;
      const filepath = path.join(PHOTOS_DIR, filename);
      fs.writeFileSync(filepath, resized);
      localPaths.push(`scraped_photos/${filename}`);
    } catch (err) {
      log(`  Ошибка скачивания фото #${i + 1}: ${err.message}`);
    }
  }
  return { downloaded: localPaths.length, localPaths };
}

// ── Logging ─────────────────────────────────────────────
let logStream = null;

function initLog() {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const logFile = path.join(LOGS_DIR, `yandex_enrich_${ts}.log`);
  logStream = fs.createWriteStream(logFile, { flags: 'a' });
  log(`Лог: ${logFile}`);
}

function log(msg) {
  const line = `[${new Date().toISOString().slice(11, 19)}] ${msg}`;
  console.log(line);
  logStream?.write(line + '\n');
}

// ── Main ────────────────────────────────────────────────
async function main() {
  const opts = parseArgs();
  fs.mkdirSync(PHOTOS_DIR, { recursive: true });
  initLog();

  log('=== Yandex Maps Enrichment ===');
  log(`Параметры: ${JSON.stringify(opts)}`);

  // 1. Получаем места
  const places = await getPlacesToEnrich(opts);
  if (places.length === 0) {
    log('Нет мест для обогащения.');
    return;
  }

  // 2. Запускаем браузер
  const browser = await chromium.launch({
    headless: false, // Для ручного решения капчи
    args: [
      '--disable-blink-features=AutomationControlled',
      '--window-size=800,600',
      '--window-position=50,50',
    ],
  });
  const context = await browser.newContext({
    userAgent:
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 800, height: 600 },
    locale: 'ru-RU',
  });
  // Закрываем браузер при Ctrl+C
  process.on('SIGINT', async () => {
    log('\n⚠ Прервано (Ctrl+C). Закрываю браузер...');
    await browser.close().catch(() => {});
    logStream?.end();
    process.exit(0);
  });

  let success = 0;
  let errors = 0;
  let noResults = 0;

  try {
  for (let i = 0; i < places.length; i++) {
    const place = places[i];
    const city = place._city || '';
    const idx = `[${i + 1}/${places.length}]`;

    // Новая вкладка на каждое место — чистое состояние
    const page = await context.newPage();

    try {
      log(`${idx} ${city} | ${place.title}`);

      // Шаг 1: Поиск на Яндекс.Картах
      await searchPlace(page, place.title, city);

      // Шаг 2: Найти первую организацию
      const orgHref = await findFirstOrgLink(page);
      if (!orgHref) {
        log(`${idx}   → нет результатов`);
        // Сохраняем запись "не найдено"
        await sbPost('/rest/v1/place_search_results_raw', [{
          place_id: place.id,
          query_text: `${place.title} ${city}`,
          provider: PROVIDER,
          rank: null,
          title: null,
          snippet: 'no_results',
          url: null,
          raw: { status: 'no_results' },
        }]);
        noResults++;
        await page.close().catch(() => {});
        await randomDelay();
        continue;
      }

      // Шаг 3: Открыть карточку
      await openOrgCard(page, orgHref);

      // Шаг 4: Навигация по карточке
      await openOverviewTab(page);
      await scrollToContactsBlock(page);
      await clickShowPhoneIfExists(page);

      // Шаг 5: Извлечение данных
      const data = await extractCardData(page);

      // Шаг 6: Скачать до 3 фото (для ревью — выбор интерьера, без людей)
      const photos = await downloadAndResizePhotos(data.photo_urls || [], place.id);

      // Шаг 7: Формируем raw jsonb
      const rawData = {
        ...data,
        photos_downloaded: photos.downloaded,
        photo_local_paths: photos.localPaths,
        // legacy-совместимость
        photo_downloaded: photos.downloaded > 0,
        photo_local_path: photos.localPaths[0] || null,
      };

      // Шаг 8: Записываем в БД
      const status = await sbPost('/rest/v1/place_search_results_raw', [{
        place_id: place.id,
        query_text: `${place.title} ${city}`,
        provider: PROVIDER,
        rank: 1,
        title: data.yandex_title || null,
        snippet: data.yandex_address || null,
        url: data.yandex_url || null,
        raw: rawData,
      }]);

      const hasPhone = data.phone ? '📞' : '  ';
      const hasSite = data.website ? '🌐' : '  ';
      const photoIcon = photos.downloaded > 0 ? `📷×${photos.downloaded}` : '  ';
      const rating = data.rating ? `★${data.rating}` : '';

      log(`${idx}   → ${data.yandex_title?.slice(0, 30) || '?'} ${hasPhone}${hasSite}${photoIcon} ${rating}`);
      success++;
    } catch (err) {
      log(`${idx}   ✗ ОШИБКА: ${err.message}`);
      errors++;
    } finally {
      // Закрываем вкладку после каждого места
      await page.close().catch(() => {});
    }

    // Rate limiting
    await randomDelay();
    if ((i + 1) % 20 === 0) {
      log(`--- Пауза 10 сек (каждые 20 мест) ---`);
      await sleep(10000);
    }
  }

  } finally {
    // Гарантированно закрываем браузер
    await browser.close().catch(() => {});
  }

  // Итоги
  log('');
  log('=== Итоги ===');
  log(`Успешно: ${success}`);
  log(`Не найдено: ${noResults}`);
  log(`Ошибки: ${errors}`);
  log(`Всего: ${places.length}`);

  logStream?.end();
}

async function randomDelay() {
  const delay = 3000 + Math.random() * 2000; // 3-5 сек
  await sleep(delay);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
