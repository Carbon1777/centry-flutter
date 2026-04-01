#!/bin/bash
# Последовательный запуск обогащения по всем оставшимся городам

CITIES=("Сочи" "Краснодар" "Новосибирск" "Нижний Новгород" "Ростов-на-Дону" "Москва" "Санкт-Петербург")
MAX_RETRIES=3

for city in "${CITIES[@]}"; do
  echo ""
  echo "========================================="
  echo "  Запуск: $city"
  echo "  $(date)"
  echo "========================================="

  for attempt in $(seq 1 $MAX_RETRIES); do
    node scripts/yandex_enrich.js --city "$city"
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
      echo "✓ $city завершён: $(date)"
      break
    else
      echo "✗ $city ошибка (попытка $attempt/$MAX_RETRIES, код $exit_code): $(date)"
      if [ $attempt -lt $MAX_RETRIES ]; then
        echo "  Пауза 30 сек перед повтором..."
        sleep 30
      fi
    fi
  done

  sleep 10
done

echo ""
echo "========================================="
echo "  ВСЕ ГОРОДА ЗАВЕРШЕНЫ"
echo "  $(date)"
echo "========================================="
