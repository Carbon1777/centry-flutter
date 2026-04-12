#!/usr/bin/env node
/**
 * TZ6 — Нормализация спарсенных мест
 * Вход: yandex_parse_all_results.json (11156)
 * Выход: yandex_parse_normalized.json
 */

const fs = require('fs');
const path = require('path');

const INPUT = path.join(__dirname, 'yandex_parse_all_results.json');
const OUTPUT = path.join(__dirname, 'yandex_parse_normalized.json');

// ============================================================
// КОНФИГ
// ============================================================

const STOP_WORDS_TITLE = [
  'магазин', 'shop', 'store', 'маркет', 'супермаркет', 'гипермаркет',
  'аптека', 'pharmacy', 'оптика',
  'фитнес', 'тренажёрн', 'тренажерн', 'спортзал', 'gym',
  'школа', 'гимназия', 'лицей', 'колледж', 'университет', 'институт', 'академия',
  'детский сад', 'детсад',
  'поликлиника', 'больница', 'клиника', 'стоматолог', 'медцентр',
  'автосервис', 'автомойка', 'шиномонтаж', 'автозапчасти',
  'прачечная', 'химчистка',
  'ритуал', 'похорон',
  'ломбард', 'займ', 'микрозайм',
  'киберспорт', 'компьютерный клуб', 'cyber',
  'массажный салон', 'массажный кабинет',
  'батут', 'trampoline',
  'квест', 'quest',
  'доставка еды', 'доставка пиццы', 'доставка суши',
  'кондитерская фабрика',
  'столовая', 'canteen',
  'хостел', 'hostel', 'гостиница', 'отель', 'hotel',
  'парикмахерская', 'салон красоты', 'барбершоп',
  'банкомат', 'atm',
  'почта', 'почтовое отделение',
  'нотариус', 'юридическ',
  'страхов',
  'турагент', 'турфирма',
  'ветеринар',
  'зоомагазин',
];

const STOP_WORDS_SITE = [
  'delivery', 'dostavka',
  'avito.ru', 'youla.ru', '//2gis.ru', '2gis.biz',
  'instagram.com', 'vk.com', 'vk.link', 'facebook.com', 'ok.ru', 't.me', 'telegram',
  'taplink.cc', 'taplink.ws', 'linktr.ee', 'tap.link',
  'wildberries', 'ozon.ru', 'yandex.market', 'yandex.ru',
  'sites.google.com', 'google.com/maps',
  'tripadvisor', 'booking.com', 'zoon.ru', 'flamp.ru',
];

const CATEGORY_MAP = {
  'Бар': 'bar',
  'Ресторан': 'restaurant',
  'Ночной клуб': 'nightclub',
  'Сауна': 'bathhouse',
  'Кальянная': 'hookah',
  'Караоке': 'karaoke',
};

// Bounding boxes городов (грубые)
const CITY_BBOX = {
  'Москва':           { latMin: 55.48, latMax: 56.01, lngMin: 37.17, lngMax: 37.96 },
  'Санкт-Петербург':  { latMin: 59.75, latMax: 60.15, lngMin: 29.40, lngMax: 30.75 },
  'Новосибирск':      { latMin: 54.82, latMax: 55.12, lngMin: 82.70, lngMax: 83.20 },
  'Казань':           { latMin: 55.70, latMax: 55.88, lngMin: 48.90, lngMax: 49.35 },
  'Ростов-на-Дону':   { latMin: 47.15, latMax: 47.35, lngMin: 39.55, lngMax: 39.85 },
  'Краснодар':        { latMin: 44.95, latMax: 45.15, lngMin: 38.85, lngMax: 39.15 },
  'Нижний Новгород':  { latMin: 56.22, latMax: 56.40, lngMin: 43.80, lngMax: 44.15 },
  'Сочи':             { latMin: 43.35, latMax: 43.75, lngMin: 39.55, lngMax: 40.25 },
};

// ============================================================
// УТИЛИТЫ
// ============================================================

const report = { total: 0, filters: {}, normalize: {} };
function countFilter(reason) {
  report.filters[reason] = (report.filters[reason] || 0) + 1;
}

/** Проверка стоп-слов (case-insensitive) */
function matchesStopWords(text, stopWords) {
  if (!text) return false;
  const lower = text.toLowerCase();
  return stopWords.some(sw => lower.includes(sw));
}

/** Нормализация телефона → E.164 (+7XXXXXXXXXX) или null */
function normalizePhone(raw) {
  if (!raw) return null;
  // Убираем всё кроме цифр и +
  let digits = raw.replace(/[^0-9+]/g, '');
  // +7... → оставляем
  if (digits.startsWith('+7') && digits.length === 12) return digits;
  if (digits.startsWith('+7')) digits = digits.slice(2);
  else if (digits.startsWith('8') && digits.length === 11) digits = digits.slice(1);
  else if (digits.startsWith('7') && digits.length === 11) digits = digits.slice(1);

  if (digits.length === 10) return '+7' + digits;
  return null; // невалидный
}

/** Нормализация сайта */
function normalizeWebsite(raw) {
  if (!raw) return null;
  let url = raw.trim().toLowerCase();

  // Стоп-сайты
  if (STOP_WORDS_SITE.some(sw => url.includes(sw))) return null;

  // Убрать www.
  url = url.replace(/^(https?:\/\/)?www\./, '$1');

  // Добавить https://
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://' + url;
  }
  // http → https
  url = url.replace(/^http:\/\//, 'https://');

  // Убрать trailing slash
  url = url.replace(/\/+$/, '');
  // Убрать query params (utm и прочее)
  url = url.replace(/\?.*$/, '');
  // Убрать якоря
  url = url.replace(/#.*$/, '');

  // Проверка что домен синтаксически валиден
  try {
    new URL(url);
  } catch {
    return null;
  }

  return url;
}

/** Нормализация адреса */
function normalizeAddress(raw, city) {
  if (!raw) return null;
  let addr = raw.trim();

  const cityEscaped = city.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

  // ШАГ 1: Отделить слипшийся текст после номера дома
  // "10Метро: Лефортово" → "10", "29Метро:" → "29", "10цоколь" → "10"
  // Паттерн: цифра[буква] + кириллица/латиница (не корп/стр/лит/к/с)
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(метро[:\s].*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(цоколь\S*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(подвал\S*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ТЦ\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ТРЦ\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ТРК\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(БЦ\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ЖК\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(МФК\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ББЦ\s.*)/g, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(Отель\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(Гостиниц\S*\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(Комплекс\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(Ресторанный\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(ориентир\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(Дворец\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(внутри\s.*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(рынок\S*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(сквер\S*)/gi, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁa-zA-Z]?)(пристройка\s.*)/gi, '$1');

  // Общий catchall: цифра + слипшийся кириллический текст (кроме к/с/лит/корп/стр + цифра)
  // "7Хамовники" → "7", "30Москворецкий" → "30", "264СНТ" → "264", но "7к2" оставить
  addr = addr.replace(/(\d+[а-яёА-ЯЁ]?)([А-ЯЁ][а-яё]{3,}.*)/g, '$1');
  addr = addr.replace(/(\d+)(СНТ\s.*)/g, '$1');
  // "6г Москва, ул Смоленская, д 6" — дубль адреса после буквы дома
  addr = addr.replace(new RegExp('(\\d+[а-яёА-ЯЁ])\\s+' + cityEscaped + '.*$', 'i'), '$1');
  // Слипшийся текст с кавычками: '4/39В5 (последний) "Петрополис"лифта нет...'
  addr = addr.replace(/(\d+[а-яёА-ЯЁ]*\d*)\s*\(.*?\).*$/g, '$1');
  // Слипшийся текст после "В5" с кавычками
  addr = addr.replace(/(\d+[а-яёА-ЯЁ]?\d*)\s*".*$/g, '$1');
  // "98гостиничного комплекса" — строчная после цифры = мусор
  addr = addr.replace(/(\d+)([а-яё]{4,}.*)/g, '$1');
  // "с1возле центрального входа" — строчная после с1
  addr = addr.replace(/(с\d+)([а-яё]{3,}.*)/gi, '$1');

  // Слипшийся город+текст в конце: "МоскваФудхолл Kitchen Garden"
  addr = addr.replace(new RegExp(',?\\s*' + cityEscaped + '[а-яёА-ЯЁa-zA-Z].*$', 'i'), '');
  // Слипшийся город+цифра/спец: "Москва1", "Москва •", "Москва\", "Краснодар​1"
  addr = addr.replace(new RegExp(',?\\s*' + cityEscaped + '[\\s\u200b]*[•\\\\\\d/:].*$', 'i'), '');

  // ШАГ 2: Убрать мусорные хвосты (через запятую)
  addr = addr.replace(/,?\s*этаж\s*\S*/gi, '');
  addr = addr.replace(/,?\s*подъезд\s*\S*/gi, '');
  addr = addr.replace(/,?\s*вход\s+.*$/gi, '');
  addr = addr.replace(/,?\s*офис\s*\S*/gi, '');
  addr = addr.replace(/,?\s*помещение\s*\S*/gi, '');
  addr = addr.replace(/,?\s*пом\.\s*\S*/gi, '');
  addr = addr.replace(/,?\s*павильон\s*\S*/gi, '');
  addr = addr.replace(/,?\s*каб\.\s*\S*/gi, '');
  addr = addr.replace(/,?\s*комн?\.\s*\S*/gi, '');
  addr = addr.replace(/,?\s*строен\.\s*\S*/gi, '');
  addr = addr.replace(/,?\s*цокольн\S*/gi, '');
  addr = addr.replace(/,?\s*подвал\S*/gi, '');
  addr = addr.replace(/,?\s*рядом с\s+.*$/gi, '');
  addr = addr.replace(/,?\s*напротив\s+.*$/gi, '');
  addr = addr.replace(/,?\s*на территории\s+.*$/gi, '');
  addr = addr.replace(/,?\s*территория\s+.*$/gi, '');
  addr = addr.replace(/,?\s*справа\s+.*$/gi, '');
  addr = addr.replace(/,?\s*слева\s+.*$/gi, '');
  addr = addr.replace(/,?\s*со стороны\s+.*$/gi, '');
  addr = addr.replace(/,?\s*через\s+.*$/gi, '');
  addr = addr.replace(/,?\s*около\s+.*$/gi, '');
  addr = addr.replace(/,?\s*метро[:\s].*$/gi, '');

  // Убрать дубли адреса внутри строки:
  // "Лужники, 24, стр. 34ул. Лужники, 24, стр. 34" — вторая половина повторяет первую
  // "Кузнечный пер., 8191025, Спб, Кузнечный пер., д. 8" — мусор после дома
  // Стратегия: после номера дома+корп+стр не должно быть ещё одной улицы
  addr = addr.replace(/(\d+[а-яёА-ЯЁ]?(?:\s*,\s*(?:корп|стр|лит)\.\s*\S+)*)\s*ул\.\s.*$/i, '$1');
  addr = addr.replace(/(\d+[а-яёА-ЯЁ]?(?:\s*,\s*(?:корп|стр|лит)\.\s*\S+)*)(\d{5,}.*$)/i, '$1'); // почтовый индекс
  // "10соор14Фуд" — слипшийся мусор с "соор" (сооружение)
  addr = addr.replace(/(\d+)(соор\S*)/gi, '$1');
  // "6, стр. 1кА5" — мусор после стр
  addr = addr.replace(/(стр\.\s*\d+)[а-яёА-ЯЁa-zA-Z]{2,}\S*/gi, '$1');
  // ФУДКОРТ и прочий мусор
  addr = addr.replace(/,?\s*ФУДКОРТ.*$/gi, '');
  addr = addr.replace(/,?\s*Фуд\s*-?\s*Сити.*$/gi, '');
  addr = addr.replace(/,?\s*фудхолл.*$/gi, '');

  // ШАГ 3: Разделяем на компоненты
  let parts = addr.split(',').map(p => p.trim()).filter(Boolean);

  // ШАГ 4: Фильтрация компонентов-мусора
  const JUNK_PATTERNS = [
    /^россия$/i,
    /район$/i,                    // "Вахитовский район", "Советский район"
    /округ$/i,                    // "Западный административный округ"
    /микрорайон/i,                // "микрорайон Центральный", "2-й микрорайон"
    /^жилой\s(массив|район)/i,   // "жилой массив Пашковский"
    /^квартал\s/i,                // "квартал № 282"
    /^городской округ/i,          // "городской округ Нижний Новгород"
    /административный/i,
    /^Инновационный центр/i,      // "Инновационный центр Сколково"
    /^Приокский/i,
    /^Фестивальный/i,
    /^Музыкальный/i,
    /^ТЦ\s/i, /^ТРЦ\s/i, /^ТРК\s/i, /^БЦ\s/i, /^ЖК\s/i, /^МФК\s/i,
    /^ББЦ\s/i,
    /^отель\s/i, /^гостиниц/i, /^hotel/i,
    /^посёлок\s/i, /^поселок\s/i, /^село\s/i, /^деревня\s/i,
    /^дачное\s/i, /^садовое\s/i, /^некоммерч/i,
    /^универмаг/i, /^универсам/i,
    /[«»"]/,                      // кавычки в компоненте = мусорное описание
    /^рынок\s/i, /^базар/i,
    /^метро/i,
    /^площадь\s+Маршала/i,
    /^район\s/i,                   // "район Коммунарка", "район Солнцево"
    /^Кросс-Док/i,
    /^Фуд/i,
    /^садовод/i, /^СНТ\b/i,       // СНТ, садоводческое товарищество
    /^исторический район/i,
    /^жилой комплекс/i, /^жилмассив/i,
    /^левое крыло$/i, /^правое крыло$/i,
    /^домофон/i,
    /^ресторан\b/i,
    /^Бар-клуб/i,
    /^Петрополис/i,
    /^лифта нет/i,
    /^\.\s*$/,                     // пустые точки
    /^возле\s/i,                   // "возле фонтана"
    /^мыс\s/i,                    // "мыс Видный"
    /^хутор\s/i,
    /^Затулинский/i,
    /^Республика\s/i,              // "Республика Татарстан (Татарстан)"
    /область$/i,                   // "Ростовская область"
    /^Краснодарский край/i,
    /сельское поселение/i,
    /^Краснокрымское/i,
  ];

  // Определяем: город, улица+дом, корп/стр/лит — оставляем. Остальное — проверяем.
  const cities = [city, 'Россия', 'Russia'];
  let cityFound = false;

  parts = parts.filter(p => {
    // Город — оставить один раз
    if (cities.includes(p)) {
      if (cityFound) return false;
      cityFound = true;
      return true;
    }
    // корп., стр., лит. — всегда оставить
    if (/^корп\b/i.test(p) || /^стр\b/i.test(p) || /^лит\b/i.test(p)) return true;
    // Номер дома (начинается с цифры) — оставить
    if (/^\d/.test(p)) return true;
    // Улица/проспект/переулок/набережная/бульвар/шоссе/площадь/линия — оставить
    if (/ул\.|улица|просп|пер\.|наб\.|бул\.|ш\.|пр\.|проезд|тупик|аллея|линия|шоссе|проспект|переулок|набережная|бульвар|площадь/i.test(p)) return true;
    // Если содержит "ая ул" / "ий просп" / etc — это улица
    if (/\s(ул|просп|пер|наб|бул|ш|пр)\./i.test(p)) return true;
    // Мусор — убрать
    if (JUNK_PATTERNS.some(pat => pat.test(p))) return false;
    // Оставить если короткий (скорее часть адреса) или содержит номер
    if (p.length < 20 && /\d/.test(p)) return true;
    // Названия улиц без явных маркеров (типа "Профсоюзная") — оставить если 2-3 компонента всего
    return true;
  });

  // Убедиться что город на первом месте
  const cityIdx = parts.findIndex(p => p === city);
  if (cityIdx > 0) {
    parts.splice(cityIdx, 1);
    parts.unshift(city);
  } else if (cityIdx === -1) {
    parts.unshift(city);
  }

  // ШАГ 5: Нормализация корпус/строение
  parts = parts.map(p => {
    // "56к2с1" → "56, корп. 2, стр. 1"
    p = p.replace(/(\d+)\s*к(\d+)\s*с(\d+)/i, '$1, корп. $2, стр. $3');
    p = p.replace(/(\d+)\s*к(\d+)/i, '$1, корп. $2');
    p = p.replace(/(\d+)\s*с(\d+)/i, '$1, стр. $2');
    // Отдельные "с1" → "стр. 1", "к2" → "корп. 2"
    if (/^с\d+$/i.test(p)) p = p.replace(/^с(\d+)$/i, 'стр. $1');
    if (/^к\d+$/i.test(p)) p = p.replace(/^к(\d+)$/i, 'корп. $1');
    return p;
  });

  // Убрать дубли типа "Москва-1", "Москва/ Селигерская" — город+мусор
  parts = parts.filter(p => {
    if (new RegExp('^' + cityEscaped + '[-/]', 'i').test(p)) return false;
    // Ресторанный/описательный мусор
    if (/^Ресторан\b|^Бар\b|^Караоке\b|^Кальянная\b|^модн/i.test(p)) return false;
    return true;
  });

  // Убрать дубль дома+улицы (если один адрес повторяется дважды)
  // "1-й Грайвороновский пр., 3А, корп. 11-й Грайвороновский проезд, 3А, корп. 1"
  if (parts.length > 5) {
    // Проверяем нет ли повтора улицы
    const streetParts = parts.filter(p => /ул\.|просп|пер\.|наб\.|бул\.|ш\.|пр\.|проезд|шоссе/i.test(p));
    if (streetParts.length >= 2) {
      // Оставляем только до второго вхождения улицы
      let streetCount = 0;
      const cutIdx = parts.findIndex(p => {
        if (/ул\.|просп|пер\.|наб\.|бул\.|ш\.|пр\.|проезд|шоссе/i.test(p)) {
          streetCount++;
          return streetCount > 1;
        }
        return false;
      });
      if (cutIdx > 0) parts = parts.slice(0, cutIdx);
    }
  }

  addr = parts.join(', ');

  // Trim trailing запятые и пробелы
  addr = addr.replace(/[,\s]+$/, '').trim();

  return addr || null;
}

/** Нормализация названия */
function normalizeTitle(raw) {
  if (!raw) return null;
  let t = raw.trim();
  // Убрать декоративные символы
  t = t.replace(/[★♦●◆▪▸►◦☆✦✧⭐🔥💎]/g, '');
  // Убрать обрамляющие кавычки
  t = t.replace(/^["«»"'"']+|["«»"'"']+$/g, '');
  // Двойные пробелы
  t = t.replace(/\s{2,}/g, ' ');
  // Trailing точки/запятые
  t = t.replace(/[.,;:]+$/, '');
  return t.trim() || null;
}

// ============================================================
// ОСНОВНАЯ ОБРАБОТКА
// ============================================================

console.log('Загрузка данных...');
const raw = JSON.parse(fs.readFileSync(INPUT, 'utf-8'));
report.total = raw.length;
console.log(`Загружено: ${raw.length} мест`);

let places = [...raw];

// --- ШАГ 1.1: Стоп-слова ---
const beforeStopWords = places.length;
places = places.filter(p => {
  if (matchesStopWords(p.title, STOP_WORDS_TITLE)) {
    countFilter('stop_word_title');
    return false;
  }
  return true;
});
console.log(`Стоп-слова в title: отфильтровано ${beforeStopWords - places.length}`);

// --- ШАГ 1.2: Город в адресе ---
const beforeCity = places.length;
places = places.filter(p => {
  if (!p.address) {
    countFilter('no_address');
    return false;
  }
  // Проверяем что город присутствует в адресе (или это адрес того же города)
  // Иногда город слипается: "Москваэтаж" — содержит "Москва"
  if (!p.address.includes(p.city)) {
    // Пробуем альтернативные написания
    const altNames = {
      'Санкт-Петербург': ['Санкт-Петербург', 'С.-Петербург', 'СПб'],
      'Ростов-на-Дону': ['Ростов-на-Дону', 'Ростов'],
      'Нижний Новгород': ['Нижний Новгород', 'Н. Новгород'],
    };
    const alts = altNames[p.city] || [];
    const found = alts.some(alt => p.address.includes(alt));
    if (!found) {
      countFilter('wrong_city');
      return false;
    }
  }
  return true;
});
console.log(`Город в адресе: отфильтровано ${beforeCity - places.length}`);

// --- ШАГ 1.3: Координаты ---
const beforeCoords = places.length;
places = places.filter(p => {
  if (!p.lat || !p.lng) {
    countFilter('no_coords');
    return false;
  }
  const bbox = CITY_BBOX[p.city];
  if (bbox) {
    if (p.lat < bbox.latMin || p.lat > bbox.latMax || p.lng < bbox.lngMin || p.lng > bbox.lngMax) {
      countFilter('coords_outside_city');
      return false;
    }
  }
  return true;
});
console.log(`Координаты: отфильтровано ${beforeCoords - places.length}`);

// --- ШАГ 1.4: Дедупликация ---
const beforeDedup = places.length;
const seen = new Map(); // key → place (лучший)
for (const p of places) {
  const key = (p.title || '').toLowerCase().trim() + '|' + (p.address || '').toLowerCase().trim();
  const existing = seen.get(key);
  if (!existing) {
    seen.set(key, p);
  } else {
    // Оставляем с лучшим рейтингом/отзывами
    if ((p.rating || 0) > (existing.rating || 0) ||
        ((p.rating || 0) === (existing.rating || 0) && (p.review_count || 0) > (existing.review_count || 0))) {
      seen.set(key, p);
    }
    countFilter('duplicate');
  }
}
places = [...seen.values()];
console.log(`Дедупликация: отфильтровано ${beforeDedup - places.length}`);

console.log(`\nПосле фильтрации: ${places.length} мест (убрано ${report.total - places.length})\n`);

// --- ШАГ 2-6: Нормализация ---
let phonesNormalized = 0, phonesLost = 0;
let sitesNormalized = 0, sitesLost = 0;
let addressesNormalized = 0;

const normalized = places.map(p => {
  // Адрес
  const normAddr = normalizeAddress(p.address, p.city);
  if (normAddr) addressesNormalized++;

  // Телефон
  const normPhone = normalizePhone(p.phone);
  if (p.phone && normPhone) phonesNormalized++;
  if (p.phone && !normPhone) phonesLost++;

  // Все телефоны
  const normPhonesAll = (p.phones_all || [])
    .map(ph => normalizePhone(ph))
    .filter(Boolean);

  // Сайт
  const normWebsite = normalizeWebsite(p.website);
  if (p.website && normWebsite) sitesNormalized++;
  if (p.website && !normWebsite) sitesLost++;

  // Название
  const normTitle = normalizeTitle(p.title);

  // Категория
  const category = CATEGORY_MAP[p.search_type] || p.search_type;

  return {
    yandex_id: p.yandex_id,
    title: normTitle,
    address: normAddr,
    category: category,
    search_type: p.search_type,
    city: p.city,
    area_name: p.area_name,
    phone: normPhone,
    phones_all: normPhonesAll,
    website: normWebsite,
    rating: p.rating,
    review_count: p.review_count,
    lat: p.lat,
    lng: p.lng,
    yandex_url: p.yandex_url,
    photo_paths: p.photo_paths,
    photo_count: p.photo_count,
  };
});

// --- Финальная статистика ---
console.log('=== НОРМАЛИЗАЦИЯ ===');
console.log(`Адреса нормализованы: ${addressesNormalized}/${normalized.length}`);
console.log(`Телефоны: ${phonesNormalized} нормализованы, ${phonesLost} невалидных (удалены)`);
console.log(`Сайты: ${sitesNormalized} нормализованы, ${sitesLost} невалидных/стоп (удалены)`);

// Статистика по городам
console.log('\n=== ПО ГОРОДАМ ===');
const byCityType = {};
for (const p of normalized) {
  const key = p.city;
  if (!byCityType[key]) byCityType[key] = { total: 0, types: {} };
  byCityType[key].total++;
  byCityType[key].types[p.category] = (byCityType[key].types[p.category] || 0) + 1;
}
for (const [city, data] of Object.entries(byCityType).sort((a,b) => b[1].total - a[1].total)) {
  console.log(`${city}: ${data.total} — ${JSON.stringify(data.types)}`);
}

console.log('\n=== ФИЛЬТРЫ ===');
for (const [reason, count] of Object.entries(report.filters).sort((a,b) => b[1] - a[1])) {
  console.log(`  ${reason}: ${count}`);
}

// Проверка: места без адреса
const noAddr = normalized.filter(p => !p.address).length;
const noPhone = normalized.filter(p => !p.phone).length;
const noSite = normalized.filter(p => !p.website).length;
console.log(`\n=== ПУСТЫЕ ПОЛЯ ===`);
console.log(`Без адреса: ${noAddr}`);
console.log(`Без телефона: ${noPhone}`);
console.log(`Без сайта: ${noSite}`);

// Сохранение
fs.writeFileSync(OUTPUT, JSON.stringify(normalized, null, 2), 'utf-8');
console.log(`\nСохранено: ${OUTPUT} (${normalized.length} мест)`);
