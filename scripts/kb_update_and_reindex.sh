#!/bin/bash
# Обновление KB документов на сервере и переиндексация
set -e

SUPABASE_URL="https://lqgzvolirohuettizkhx.supabase.co"
SUPABASE_KEY="SUPABASE_SERVICE_KEY_REDACTED"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Document IDs
DOC_BZ="a0000000-0000-0000-0000-000000000001"
DOC_PRAVILA="a0000000-0000-0000-0000-000000000002"
DOC_FAQ="a0000000-0000-0000-0000-000000000003"

update_doc() {
  local doc_id="$1"
  local file_path="$2"
  local doc_name="$3"

  echo "=== Обновление: $doc_name ==="

  # Получаем ID активной версии
  local version_id
  version_id=$(curl -s -X GET \
    "${SUPABASE_URL}/rest/v1/kb_document_versions?document_id=eq.${doc_id}&is_active=eq.true&select=id,version_no&limit=1" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")

  if [ -z "$version_id" ]; then
    echo "  ОШИБКА: нет активной версии для $doc_name"
    return 1
  fi

  local version_no
  version_no=$(curl -s -X GET \
    "${SUPABASE_URL}/rest/v1/kb_document_versions?document_id=eq.${doc_id}&is_active=eq.true&select=version_no&limit=1" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['version_no'] if d else 0)")

  local new_version_no=$((version_no + 1))
  echo "  Текущая версия: v${version_no} (${version_id})"
  echo "  Новая версия: v${new_version_no}"

  # Читаем содержимое файла
  local content
  content=$(cat "$file_path")

  # Деактивируем старую версию
  curl -s -o /dev/null -X PATCH \
    "${SUPABASE_URL}/rest/v1/kb_document_versions?id=eq.${version_id}" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"is_active": false}'

  # Создаём новую версию
  local payload
  payload=$(python3 -c "
import json, sys
content = open('$file_path', 'r').read()
print(json.dumps({
    'document_id': '$doc_id',
    'version_no': $new_version_no,
    'content_markdown': content,
    'is_active': True,
    'published_at': '$(date -u +%Y-%m-%dT%H:%M:%S+00:00)'
}))
")

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${SUPABASE_URL}/rest/v1/kb_document_versions" \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    -d "$payload")

  if [ "$status" = "201" ]; then
    echo "  ✓ Версия v${new_version_no} создана"
  else
    echo "  ✗ Ошибка создания версии: HTTP $status"
    # Откатываем деактивацию
    curl -s -o /dev/null -X PATCH \
      "${SUPABASE_URL}/rest/v1/kb_document_versions?id=eq.${version_id}" \
      -H "apikey: ${SUPABASE_KEY}" \
      -H "Authorization: Bearer ${SUPABASE_KEY}" \
      -H "Content-Type: application/json" \
      -d '{"is_active": true}'
    return 1
  fi

  # Индексация
  echo "  Индексация..."
  local ingest_result
  ingest_result=$(curl -s -X POST \
    "${SUPABASE_URL}/functions/v1/kb-ingest" \
    -H "Authorization: Bearer ${SUPABASE_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"document_id\": \"${doc_id}\"}")

  echo "  $ingest_result"
  echo ""
}

echo ""
echo "======================================"
echo "  KB Update & Reindex"
echo "  $(date)"
echo "======================================"
echo ""

update_doc "$DOC_PRAVILA" "$PROJECT_DIR/Pravila_chat.md" "Правила чата"
update_doc "$DOC_FAQ"     "$PROJECT_DIR/SupportFAQ.md"    "Support FAQ"
update_doc "$DOC_BZ"      "$PROJECT_DIR/BZ.md"            "База знаний"

echo "======================================"
echo "  ГОТОВО"
echo "======================================"
