#!/usr/bin/env node
/**
 * Debug: открывает карточку на Яндекс.Картах и дампит HTML + все тексты.
 * Использование: node scripts/yandex_debug.js "100Dal Казань"
 */
import { chromium } from 'playwright';
import fs from 'fs';

const query = process.argv[2] || '100Dal Казань';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const browser = await chromium.launch({
    headless: false,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1440, height: 900 },
    locale: 'ru-RU',
  });
  const page = await context.newPage();

  // 1. Поиск
  const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;
  console.log(`Открываю: ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(5000);

  // 2. Кликаем первую организацию
  const orgLinks = await page.$$('a[href*="/maps/org/"]');
  if (orgLinks.length === 0) {
    console.log('Нет ссылок на организацию!');
    // Дампим HTML поиска
    const searchHtml = await page.content();
    fs.writeFileSync('debug_search.html', searchHtml);
    console.log('Записал debug_search.html');
    await browser.close();
    return;
  }
  const href = await orgLinks[0].getAttribute('href');
  const fullUrl = href.startsWith('http') ? href : `https://yandex.ru${href}`;
  console.log(`Открываю карточку: ${fullUrl}`);
  await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(5000);

  // 3. Скроллим
  const scrollable = await page.$('.scroll__container');
  if (scrollable) {
    for (let i = 0; i < 8; i++) {
      await scrollable.evaluate((el) => el.scrollBy(0, 400));
      await sleep(500);
    }
  }
  await sleep(2000);

  // 4. Дампим DOM-анализ
  const analysis = await page.evaluate(() => {
    const info = {};

    // Все элементы с class содержащим rating
    info.rating_elements = [];
    document.querySelectorAll('[class*="rating"]').forEach(el => {
      info.rating_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 100),
      });
    });

    // Все элементы с class содержащим phone
    info.phone_elements = [];
    document.querySelectorAll('[class*="phone"], a[href^="tel:"]').forEach(el => {
      info.phone_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 100),
        href: el.getAttribute('href'),
      });
    });

    // Все элементы с class содержащим hours / working / status
    info.hours_elements = [];
    document.querySelectorAll('[class*="hours"], [class*="working"], [class*="status"]').forEach(el => {
      info.hours_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 150),
      });
    });

    // Все элементы с class содержащим website / urls / link
    info.website_elements = [];
    document.querySelectorAll('[class*="website"], [class*="urls-view"]').forEach(el => {
      info.website_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 100),
        href: el.getAttribute('href'),
      });
    });

    // Все элементы с class содержащим address
    info.address_elements = [];
    document.querySelectorAll('[class*="address"]').forEach(el => {
      info.address_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 100),
      });
    });

    // Все элементы с class содержащим category
    info.category_elements = [];
    document.querySelectorAll('[class*="category"]').forEach(el => {
      info.category_elements.push({
        tag: el.tagName,
        class: el.className,
        text: el.textContent?.trim()?.slice(0, 100),
      });
    });

    // H1
    info.h1 = [];
    document.querySelectorAll('h1').forEach(el => {
      info.h1.push({ class: el.className, text: el.textContent?.trim()?.slice(0, 100) });
    });

    // Img элементы (первые 10)
    info.images = [];
    document.querySelectorAll('img').forEach((el, i) => {
      if (i < 15) {
        info.images.push({
          src: el.src?.slice(0, 150),
          class: el.className,
          width: el.naturalWidth,
          height: el.naturalHeight,
        });
      }
    });

    return info;
  });

  console.log('\n=== DOM Analysis ===\n');
  console.log(JSON.stringify(analysis, null, 2));

  // Сохраняем HTML
  const html = await page.content();
  fs.writeFileSync('debug_card.html', html);
  console.log('\nЗаписал debug_card.html');

  await browser.close();
}

main().catch(console.error);
