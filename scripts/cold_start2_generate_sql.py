#!/usr/bin/env python3
"""
Cold Start 2 — генерация SQL для создания 250 пользователей.
Выводит батчи SQL для выполнения через MCP execute_sql.
Сохраняет mapping auth_user_id ↔ app_user_id в отдельный файл.
"""

import json, uuid, os
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '.env'))

BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
MANIFEST = os.path.join(BASE, "manifest.json")
OUTPUT_DIR = os.path.join(BASE, "sql_batches")
MAPPING_FILE = os.path.join(BASE, "user_mapping.json")

SUPABASE_URL = os.environ["SUPABASE_URL"]
EMAIL_START = 361  # cs_user_0361 and onwards


def escape_sql(s):
    """Экранирует строку для SQL."""
    return s.replace("'", "''")


def pg_array(items):
    """Формирует PostgreSQL массив."""
    if not items:
        return "ARRAY[]::text[]"
    escaped = [f"'{escape_sql(i)}'" for i in items]
    return f"ARRAY[{','.join(escaped)}]::text[]"


def make_unique_display_names(manifest):
    """Добавляет цифры к дублирующимся никам для уникальности display_name."""
    from collections import Counter
    nick_counts = Counter(u['nickname'] for u in manifest)
    duplicates = {k for k, v in nick_counts.items() if v > 1}
    seen = {}
    for user in manifest:
        nick = user['nickname']
        if nick in duplicates:
            seen[nick] = seen.get(nick, 0) + 1
            user['display_name_unique'] = f"{nick}{seen[nick]}"
        else:
            user['display_name_unique'] = nick


def main():
    with open(MANIFEST, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    make_unique_display_names(manifest)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    mapping = []
    all_sql_blocks = []

    for idx, user in enumerate(manifest):
        email_num = EMAIL_START + idx
        email = f"cs_user_{email_num:04d}@coldstart.centry.internal"
        auth_id = str(uuid.uuid4())
        app_id = str(uuid.uuid4())

        # Avatar URL
        if user['avatar_kind'] == 'custom':
            avatar_url = f"{SUPABASE_URL}/storage/v1/object/public/avatars/custom/{auth_id}/avatar.webp"
        else:
            avatar_url = None

        # Profile photos (album) — pre-generate UUIDs for storage keys
        photo_records = []
        album_photos = [p for p in user['photos'] if p['type'] == 'album']
        for sort_idx, photo in enumerate(album_photos, 1):
            photo_id = str(uuid.uuid4())
            storage_uuid = str(uuid.uuid4())
            storage_key = f"{auth_id}/{storage_uuid}.webp"
            w = photo.get('webp_width', photo.get('width', 0))
            h = photo.get('webp_height', photo.get('height', 0))
            sz = photo.get('webp_size_bytes', photo.get('size_bytes', 0))
            photo_records.append({
                'id': photo_id,
                'storage_key': storage_key,
                'storage_uuid': storage_uuid,
                'sort_order': sort_idx,
                'width': w,
                'height': h,
                'size_bytes': sz,
                'original_filename': photo['filename'],
            })

        # Save mapping
        mapping.append({
            'idx': idx,
            'email': email,
            'auth_user_id': auth_id,
            'app_user_id': app_id,
            'folder_path': f"{user['city_slug']}/{user['district_slug']}/{user['team_slug']}/{user['folder_name']}",
            'avatar_kind': user['avatar_kind'],
            'is_closed': user['is_closed'],
            'photos': photo_records,
        })

        # Generate SQL block
        sql = f"""
-- User {idx+1}: {user['folder_name']} ({user['city_slug']}/{user['district_slug']}/{user['team_slug']})
DO $$
DECLARE
  v_auth_id uuid := '{auth_id}';
  v_app_id uuid := '{app_id}';
BEGIN
  -- 1. auth.users
  INSERT INTO auth.users (id, instance_id, email, encrypted_password, raw_user_meta_data, email_confirmed_at, created_at, updated_at, aud, role)
  VALUES (
    v_auth_id,
    '00000000-0000-0000-0000-000000000000',
    '{email}',
    '$2a$10$dummyhashforcoldstartusers',
    '{{"cold_start": true, "email_verified": true}}'::jsonb,
    now(), now(), now(), 'authenticated', 'authenticated'
  );

  -- 2. app_users
  INSERT INTO app_users (id, auth_user_id, display_name, state)
  VALUES (v_app_id, v_auth_id, '{escape_sql(user["display_name_unique"])}', 'USER');

  -- 3. user_profiles
  INSERT INTO user_profiles (user_id, nickname, name, gender, age, rest_preferences, rest_dislikes, avatar_kind, avatar_url, city)
  VALUES (
    v_app_id,
    '{escape_sql(user["nickname"])}',
    '{escape_sql(user["display_name"])}',
    '{user["gender"]}',
    {user["age"]},
    {pg_array(user["rest_preferences"])},
    {pg_array(user["rest_dislikes"])},
    '{user["avatar_kind"]}',
    {f"'{avatar_url}'" if avatar_url else "NULL"},
    '{escape_sql(user["city_display"])}'
  );

  -- 4. cold_start_registry
  INSERT INTO cold_start_registry (app_user_id, auth_user_id, city_slug, district_slug, team_slug, folder_name, is_closed)
  VALUES (
    v_app_id, v_auth_id,
    '{escape_sql(user["city_slug"])}',
    '{escape_sql(user["district_slug"])}',
    '{escape_sql(user["team_slug"])}',
    '{escape_sql(user["folder_name"])}',
    {str(user["is_closed"]).lower()}
  );
"""

        # 5. profile_photos
        for pr in photo_records:
            sql += f"""
  INSERT INTO profile_photos (id, user_id, storage_key, sort_order, status, width, height, mime_type, size_bytes)
  VALUES (
    '{pr["id"]}', v_app_id, '{pr["storage_key"]}', {pr["sort_order"]}, 'ready',
    {pr["width"]}, {pr["height"]}, 'image/webp', {pr["size_bytes"]}
  );
"""

        sql += "\nEND $$;\n"
        all_sql_blocks.append(sql)

    # Save mapping
    with open(MAPPING_FILE, 'w', encoding='utf-8') as f:
        json.dump(mapping, f, ensure_ascii=False, indent=2)
    print(f"Mapping saved: {MAPPING_FILE} ({len(mapping)} users)")

    # Save SQL in batches of 10
    batch_size = 10
    for i in range(0, len(all_sql_blocks), batch_size):
        batch = all_sql_blocks[i:i+batch_size]
        batch_num = i // batch_size + 1
        batch_file = os.path.join(OUTPUT_DIR, f"batch_{batch_num:02d}.sql")
        with open(batch_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(batch))
        print(f"Batch {batch_num}: users {i+1}-{min(i+batch_size, len(all_sql_blocks))} -> {batch_file}")

    print(f"\nTotal: {len(all_sql_blocks)} users in {(len(all_sql_blocks) + batch_size - 1) // batch_size} batches")


if __name__ == '__main__':
    main()
