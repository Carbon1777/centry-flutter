#!/usr/bin/env node
/**
 * Парсер Яндекс.Карт v2 — остальные 6 городов (41 район × 6 типов = 246 запросов)
 * Казань, Краснодар, Нижний Новгород, Новосибирск, Ростов-на-Дону, Сочи
 *
 * Запуск:  node scripts/yandex_parse_other.js
 * Пауза:  ввести "pause" + Enter в терминале
 * Стоп:   Ctrl+C (прогресс сохранится)
 */
import { createParser, AREAS } from './yandex_parse_common.js';

const parser = createParser('yandex_parse_other', {
  'Казань': AREAS['Казань'],
  'Краснодар': AREAS['Краснодар'],
  'Нижний Новгород': AREAS['Нижний Новгород'],
  'Новосибирск': AREAS['Новосибирск'],
  'Ростов-на-Дону': AREAS['Ростов-на-Дону'],
  'Сочи': AREAS['Сочи'],
});

parser.run().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
