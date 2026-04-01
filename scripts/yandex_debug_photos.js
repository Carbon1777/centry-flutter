#!/usr/bin/env node
/**
 * Debug: анализ галереи фото на карточке Яндекс.Карт.
 * node scripts/yandex_debug_photos.js "Кафе Пушкинъ Москва"
 */
import { chromium } from 'playwright';

const query = process.argv[2] || '12 Футов Казань';
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

  // 1. Поиск → карточка
  const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;
  console.log(`Открываю: ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(5000);

  const orgLinks = await page.$$('a[href*="/maps/org/"]');
  if (!orgLinks.length) { console.log('Нет организации'); await browser.close(); return; }
  const href = await orgLinks[0].getAttribute('href');
  const fullUrl = href.startsWith('http') ? href : `https://yandex.ru${href}`;
  await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await sleep(5000);

  // 2. Ищем кнопку/ссылку галереи фото
  console.log('\n=== Анализ фото-элементов на карточке ===\n');

  const photoAnalysis = await page.evaluate(() => {
    const info = {};

    // Ищем табы/фильтры фото (Интерьер, Фасад, Меню и т.д.)
    info.photo_tabs = [];
    document.querySelectorAll('[class*="gallery"] [class*="tab"], [class*="photo"] [class*="tab"], [class*="media"] [class*="tab"]').forEach(el => {
      info.photo_tabs.push({ class: el.className, text: el.textContent?.trim()?.slice(0, 80) });
    });

    // Ищем ссылки с "фото" в тексте
    info.photo_links = [];
    document.querySelectorAll('a, button, span').forEach(el => {
      const t = el.textContent?.trim() || '';
      if (t.length < 80 && /фото|photo|галерея|gallery|интерьер|interior|фасад/i.test(t)) {
        info.photo_links.push({ tag: el.tagName, class: el.className?.slice(0, 80), text: t, href: el.getAttribute('href')?.slice(0, 100) });
      }
    });

    // Ищем все элементы с class содержащим gallery / media / carousel / photo-filter
    info.gallery_elements = [];
    document.querySelectorAll('[class*="gallery"], [class*="media-view"], [class*="carousel"], [class*="photo-filter"], [class*="photo-tab"]').forEach(el => {
      if (el.children.length < 20) {
        info.gallery_elements.push({ tag: el.tagName, class: el.className?.slice(0, 120), text: el.textContent?.trim()?.slice(0, 100), childCount: el.children.length });
      }
    });

    // Все img с avatars.mds.yandex.net — проверяем alt, title, data-атрибуты
    info.yandex_images = [];
    document.querySelectorAll('img[src*="avatars.mds.yandex.net"]').forEach((img, i) => {
      if (i < 20) {
        info.yandex_images.push({
          src: img.src?.slice(0, 120),
          alt: img.alt?.slice(0, 80),
          title: img.title?.slice(0, 80),
          class: img.className,
          parentClass: img.parentElement?.className?.slice(0, 80),
          grandparentClass: img.parentElement?.parentElement?.className?.slice(0, 80),
          width: img.naturalWidth,
          height: img.naturalHeight,
          dataAttrs: Object.keys(img.dataset),
        });
      }
    });

    return info;
  });

  console.log(JSON.stringify(photoAnalysis, null, 2));

  // 3. Попробуем кликнуть на фото чтобы открыть галерею
  console.log('\n=== Пробуем открыть галерею ===\n');

  const photoClickTarget = await page.$('.orgpage-gallery-view img, .business-gallery img, img.img-with-alt');
  if (photoClickTarget) {
    await photoClickTarget.click();
    await sleep(3000);

    const galleryAnalysis = await page.evaluate(() => {
      const info = {};

      // Ищем табы/фильтры в открытой галерее
      info.gallery_tabs = [];
      document.querySelectorAll('[class*="filter"], [class*="tab"], [class*="tag"]').forEach(el => {
        const t = el.textContent?.trim();
        if (t && t.length < 50 && /интерьер|фасад|меню|еда|блюд|атмосфер|photo|все фото|all/i.test(t)) {
          info.gallery_tabs.push({ tag: el.tagName, class: el.className?.slice(0, 100), text: t });
        }
      });

      // Все кнопки/ссылки в галерее
      info.gallery_buttons = [];
      document.querySelectorAll('[class*="gallery"] button, [class*="gallery"] a, [class*="media"] button, [class*="viewer"] button').forEach(el => {
        const t = el.textContent?.trim();
        if (t && t.length < 50) {
          info.gallery_buttons.push({ tag: el.tagName, class: el.className?.slice(0, 100), text: t });
        }
      });

      // Проверяем URL — может галерея открылась на отдельной странице
      info.currentUrl = window.location.href;

      // Все фильтр-элементы
      info.all_filters = [];
      document.querySelectorAll('[class*="filter"]').forEach(el => {
        info.all_filters.push({ tag: el.tagName, class: el.className?.slice(0, 120), text: el.textContent?.trim()?.slice(0, 100) });
      });

      return info;
    });

    console.log(JSON.stringify(galleryAnalysis, null, 2));
  }

  await browser.close();
}

main().catch(console.error);
