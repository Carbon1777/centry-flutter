#!/usr/bin/env node
/**
 * TZ5 Разведка — сколько мест на Яндекс.Картах по рубрикам × городам.
 * Скроллит список результатов, считает карточки, рейтинги, фото.
 *
 * Использование:
 *   node scripts/yandex_recon.js
 *   node scripts/yandex_recon.js --category "Бар"
 *   node scripts/yandex_recon.js --city "Москва"
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RESULTS_FILE = path.join(__dirname, 'recon_results.json');

const CITIES = [
  'Москва', 'Санкт-Петербург', 'Новосибирск', 'Нижний Новгород',
  'Ростов-на-Дону', 'Казань', 'Сочи', 'Краснодар',
];

const CATEGORIES = [
  'Бар', 'Ресторан', 'Ночной клуб', 'Сауна', 'Кальянная', 'Караоке',
];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { city: null, category: null };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--city' && args[i + 1]) opts.city = args[++i];
    if (args[i] === '--category' && args[i + 1]) opts.category = args[++i];
  }
  return opts;
}

async function waitForCaptcha(page) {
  if (!page.url().includes('showcaptcha')) return;
  console.log('  ⚠ CAPTCHA! Реши в браузере...');
  while (page.url().includes('showcaptcha')) {
    await sleep(2000);
  }
  console.log('  ✓ Captcha solved');
  await sleep(3000);
}

async function scrollListToEnd(page, maxScrolls = 150) {
  // Скроллим список результатов до конца (или до лимита)
  let prevCount = 0;
  let sameCountStreak = 0;

  for (let i = 0; i < maxScrolls; i++) {
    // Скролл списка
    await page.evaluate(() => {
      const scrollable = document.querySelector('.scroll__container');
      if (scrollable) {
        scrollable.scrollBy(0, 800);
      }
    });
    await sleep(600);

    // Проверяем капчу
    await waitForCaptcha(page);

    // Считаем текущее количество карточек
    const currentCount = await page.evaluate(() => {
      return document.querySelectorAll('.search-snippet-view').length;
    });

    if (currentCount === prevCount) {
      sameCountStreak++;
      if (sameCountStreak >= 5) {
        // Список закончился
        break;
      }
    } else {
      sameCountStreak = 0;
    }

    prevCount = currentCount;

    // Лог каждые 20 скроллов
    if ((i + 1) % 20 === 0) {
      process.stdout.write(`  скролл ${i + 1}, карточек: ${currentCount}\r`);
    }
  }
  console.log('');
  return prevCount;
}

async function collectStats(page) {
  // Собираем данные из всех загруженных карточек
  return page.evaluate(() => {
    const snippets = document.querySelectorAll('.search-snippet-view');
    let total = 0;
    let withRating = 0;
    let rating40plus = 0;
    let rating45plus = 0;
    let withPhoto = 0;
    const ratings = [];

    for (const snippet of snippets) {
      total++;

      // Рейтинг — из .business-rating-badge-view__rating-text внутри сниппета
      const ratingEl = snippet.querySelector('.business-rating-badge-view__rating-text');
      if (ratingEl) {
        const rText = ratingEl.textContent.trim().replace(',', '.');
        const rating = parseFloat(rText);
        if (!isNaN(rating)) {
          withRating++;
          ratings.push(rating);
          if (rating >= 4.0) rating40plus++;
          if (rating >= 4.5) rating45plus++;
        }
      }

      // Фото — .search-business-snippet-view__photo или img внутри gallery
      const photoEl = snippet.querySelector(
        '.search-business-snippet-view__photo, .search-business-snippet-view__gallery img'
      );
      if (photoEl) {
        withPhoto++;
      }
    }

    return {
      total,
      withRating,
      rating40plus,
      rating45plus,
      withPhoto,
    };
  });
}

async function reconQuery(page, category, city) {
  const query = `${category} ${city}`;
  const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;

  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(6000);
  await waitForCaptcha(page);

  // Скроллим до конца списка
  const scrolledCount = await scrollListToEnd(page);

  // Собираем статистику
  const stats = await collectStats(page);

  return {
    category,
    city,
    total: stats.total,
    with_rating: stats.withRating,
    rating_40_plus: stats.rating40plus,
    rating_45_plus: stats.rating45plus,
    with_photo: stats.withPhoto,
    pct_rating_40: stats.withRating > 0
      ? Math.round((stats.rating40plus / stats.withRating) * 100) : null,
    pct_rating_45: stats.withRating > 0
      ? Math.round((stats.rating45plus / stats.withRating) * 100) : null,
    pct_photo: stats.total > 0
      ? Math.round((stats.withPhoto / stats.total) * 100) : null,
  };
}

async function main() {
  const opts = parseArgs();
  const cities = opts.city ? [opts.city] : CITIES;
  const categories = opts.category ? [opts.category] : CATEGORIES;

  const totalQueries = cities.length * categories.length;
  console.log(`\n=== Яндекс.Карты — Разведка ===`);
  console.log(`Категорий: ${categories.length}, Городов: ${cities.length}, Запросов: ${totalQueries}\n`);

  const browser = await chromium.launch({
    headless: false,
    args: ['--disable-blink-features=AutomationControlled', '--window-size=1000,800'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1000, height: 800 },
    locale: 'ru-RU',
  });

  // Загрузка предыдущих результатов
  let results = [];
  if (fs.existsSync(RESULTS_FILE)) {
    try {
      results = JSON.parse(fs.readFileSync(RESULTS_FILE, 'utf-8'));
      console.log(`Загружено ${results.length} предыдущих результатов\n`);
    } catch { /* игнор */ }
  }

  process.on('SIGINT', async () => {
    console.log('\n⚠ Прервано. Сохраняю...');
    fs.writeFileSync(RESULTS_FILE, JSON.stringify(results, null, 2));
    await browser.close().catch(() => {});
    process.exit(0);
  });

  const page = await context.newPage();
  let idx = 0;

  for (const city of cities) {
    for (const category of categories) {
      idx++;

      // Пропускаем если уже есть
      if (results.find(r => r.city === city && r.category === category)) {
        console.log(`[${idx}/${totalQueries}] ${category} × ${city} — уже есть, пропускаю`);
        continue;
      }

      console.log(`[${idx}/${totalQueries}] ${category} × ${city}...`);

      try {
        const result = await reconQuery(page, category, city);
        results.push(result);

        console.log(`  → Всего: ${result.total} | С рейтингом: ${result.with_rating} | ≥4.0: ${result.rating_40_plus} (${result.pct_rating_40}%) | ≥4.5: ${result.rating_45_plus} (${result.pct_rating_45}%) | С фото: ${result.with_photo} (${result.pct_photo}%)`);

        // Сохраняем после каждого
        fs.writeFileSync(RESULTS_FILE, JSON.stringify(results, null, 2));
      } catch (err) {
        console.log(`  ✗ Ошибка: ${err.message}`);
        results.push({ category, city, error: err.message, total: null });
      }

      // Пауза
      const delay = 4000 + Math.random() * 3000;
      await sleep(delay);
    }
  }

  await browser.close();

  // Итоговая таблица
  console.log('\n\n=== ИТОГИ ===\n');
  console.log(
    'Город'.padEnd(20) + '| ' +
    'Категория'.padEnd(15) + '| ' +
    'Всего'.padStart(6) + ' | ' +
    '≥4.0'.padStart(5) + ' | ' +
    '≥4.5'.padStart(5) + ' | ' +
    'Фото'.padStart(5) + ' |'
  );
  console.log('-'.repeat(75));

  let grandTotal = 0;
  let grand40 = 0;
  let grand45 = 0;

  for (const r of results) {
    if (r.error) {
      console.log(`${(r.city || '').padEnd(20)}| ${(r.category || '').padEnd(15)}| ОШИБКА`);
      continue;
    }
    console.log(
      (r.city || '').padEnd(20) + '| ' +
      (r.category || '').padEnd(15) + '| ' +
      String(r.total ?? '?').padStart(6) + ' | ' +
      String(r.rating_40_plus ?? '?').padStart(5) + ' | ' +
      String(r.rating_45_plus ?? '?').padStart(5) + ' | ' +
      String(r.with_photo ?? '?').padStart(5) + ' |'
    );
    grandTotal += (r.total || 0);
    grand40 += (r.rating_40_plus || 0);
    grand45 += (r.rating_45_plus || 0);
  }

  console.log('-'.repeat(75));
  console.log(`ИТОГО: ${grandTotal} мест | ≥4.0: ${grand40} | ≥4.5: ${grand45}`);
  console.log(`\nРезультаты: ${RESULTS_FILE}`);
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
