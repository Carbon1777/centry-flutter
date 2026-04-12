#!/usr/bin/env node
/**
 * Дамп DOM страницы Яндекс.Карт для анализа селекторов.
 */
import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const browser = await chromium.launch({
    headless: false,
    args: ['--disable-blink-features=AutomationControlled', '--window-size=1200,800'],
  });
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    viewport: { width: 1200, height: 800 },
    locale: 'ru-RU',
  });

  const page = await context.newPage();
  const query = 'Бар Москва';
  const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;

  console.log(`Открываю: ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(7000);

  // Проверка капчи
  if (page.url().includes('showcaptcha')) {
    console.log('⚠ CAPTCHA! Реши в браузере...');
    while (page.url().includes('showcaptcha')) {
      await sleep(2000);
    }
    console.log('✓ Captcha solved');
    await sleep(5000);
  }

  // Скроллим список для подгрузки
  for (let i = 0; i < 3; i++) {
    await page.evaluate(() => {
      const scrollable = document.querySelector('.scroll__container');
      if (scrollable) scrollable.scrollBy(0, 500);
    });
    await sleep(1000);
  }

  // Сохраняем HTML
  const html = await page.content();
  const outPath = path.join(__dirname, 'yandex_dom_dump.html');
  fs.writeFileSync(outPath, html);
  console.log(`\nHTML сохранён: ${outPath} (${(html.length / 1024).toFixed(0)} KB)`);

  // Быстрый анализ — ищем паттерны с числами и "организаци"/"мест"
  console.log('\n=== Поиск текста с количеством ===');
  const textContent = await page.evaluate(() => document.body.innerText);
  const lines = textContent.split('\n').filter(l =>
    /организаци|мест\b|найдено|нашлось|результат/i.test(l)
  );
  for (const line of lines.slice(0, 10)) {
    console.log(`  "${line.trim().slice(0, 120)}"`);
  }

  // Ищем элементы с рейтингом
  console.log('\n=== Элементы с рейтингами ===');
  const ratings = await page.evaluate(() => {
    const results = [];
    const allEls = document.querySelectorAll('*');
    for (const el of allEls) {
      const text = el.textContent?.trim() || '';
      const cls = el.className || '';
      if (/^\d[.,]\d$/.test(text) && text.length <= 3) {
        results.push({
          tag: el.tagName,
          class: typeof cls === 'string' ? cls.slice(0, 100) : '',
          text,
          parentClass: (el.parentElement?.className || '').slice(0, 100),
        });
      }
    }
    return results.slice(0, 20);
  });
  for (const r of ratings) {
    console.log(`  <${r.tag} class="${r.class}"> ${r.text} (parent: ${r.parentClass})`);
  }

  // Ищем карточки/сниппеты в списке
  console.log('\n=== Карточки в списке (поиск сниппетов) ===');
  const snippets = await page.evaluate(() => {
    const results = [];
    // Ищем li элементы или div с ролью listitem
    const items = document.querySelectorAll(
      'li[class*="search"], div[class*="snippet"], div[class*="SearchSnippet"], ul[class*="search"] > li'
    );
    results.push(`Найдено li/snippet: ${items.length}`);

    // Ищем все ul в sidebar
    const lists = document.querySelectorAll('ul');
    for (const ul of lists) {
      const children = ul.children.length;
      if (children >= 5) {
        results.push(`<ul class="${(ul.className || '').slice(0, 80)}"> children: ${children}`);
      }
    }

    // Ищем data-id атрибуты (Яндекс часто помечает карточки)
    const dataIds = document.querySelectorAll('[data-id]');
    results.push(`Элементов с data-id: ${dataIds.length}`);
    for (const el of [...dataIds].slice(0, 5)) {
      results.push(`  data-id="${el.getAttribute('data-id')}" class="${(el.className || '').slice(0, 80)}"`);
    }

    return results;
  });
  for (const s of snippets) {
    console.log(`  ${s}`);
  }

  // Ищем счётчик результатов
  console.log('\n=== Поиск счётчика результатов ===');
  const counters = await page.evaluate(() => {
    const results = [];
    const allEls = document.querySelectorAll('*');
    for (const el of allEls) {
      const text = el.textContent?.trim() || '';
      // Ищем число + "организаци" или "мест" или "результат"
      if (/^\d[\d\s]*\s*(организаци|мест\b|результат)/i.test(text) && text.length < 50) {
        results.push({
          tag: el.tagName,
          class: (el.className || '').slice(0, 100),
          text: text.slice(0, 80),
        });
      }
    }
    return results.slice(0, 10);
  });
  for (const c of counters) {
    console.log(`  <${c.tag} class="${c.class}"> "${c.text}"`);
  }

  await browser.close();
  console.log('\nГотово.');
}

main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});
