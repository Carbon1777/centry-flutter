#!/usr/bin/env python3
"""
Cold Start 2 — деплой 250 пользователей в Supabase.
1. Создаёт записи в БД (auth, app_users, profiles, registry, photos)
2. Загружает фото в Storage (avatars + profile-photos)

Использует mapping из cold_start2_generate_sql.py
"""

import json, os, sys, time, urllib.request, urllib.error

BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
WEBP_DIR = os.path.join(BASE, "webp")
MANIFEST = os.path.join(BASE, "manifest.json")
MAPPING_FILE = os.path.join(BASE, "user_mapping.json")
SQL_DIR = os.path.join(BASE, "sql_batches")
PROGRESS_FILE = os.path.join(BASE, "deploy_progress.json")

SUPABASE_URL = "https://lqgzvolirohuettizkhx.supabase.co"
SERVICE_KEY = "SUPABASE_SERVICE_KEY_REDACTED"


def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {"db_batches_done": [], "uploads_done": []}


def save_progress(progress):
    with open(PROGRESS_FILE, 'w') as f:
        json.dump(progress, f)


def execute_sql(sql):
    """Выполняет SQL через Supabase REST API (pg_query)."""
    url = f"{SUPABASE_URL}/rest/v1/rpc/pg_query"
    # Alternatively use the SQL endpoint
    # Actually, Supabase doesn't expose pg_query. Use the PostgreSQL REST endpoint.
    # Let's use the direct SQL execution via the management API
    # Or better: use the /pg endpoint

    # Supabase exposes SQL via POST to /rest/v1/rpc but only for existing functions
    # For raw SQL, we need to use the pg endpoint or the SQL editor API

    # Using the Supabase SQL API (undocumented but used by dashboard)
    url = f"{SUPABASE_URL}/pg/query"
    data = json.dumps({"query": sql}).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
        "apikey": SERVICE_KEY,
    })
    try:
        resp = urllib.request.urlopen(req, timeout=60)
        return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        raise Exception(f"SQL error {e.code}: {error_body}")


def upload_file(bucket, path, filepath, content_type="image/webp"):
    """Загружает файл в Supabase Storage."""
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}"

    with open(filepath, 'rb') as f:
        data = f.read()

    req = urllib.request.Request(url, data=data, method='POST', headers={
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": content_type,
        "apikey": SERVICE_KEY,
        "x-upsert": "true",
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return True
    except urllib.error.HTTPError as e:
        if e.code == 409:  # already exists
            return True
        error_body = e.read().decode()
        print(f"    Upload error {e.code} for {path}: {error_body}")
        return False


def phase_db(progress):
    """Фаза 1: создание записей в БД."""
    print("\n=== PHASE 1: DB Records ===")

    batch_files = sorted([f for f in os.listdir(SQL_DIR) if f.endswith('.sql')])
    total = len(batch_files)
    done = len(progress["db_batches_done"])

    for i, batch_file in enumerate(batch_files, 1):
        if batch_file in progress["db_batches_done"]:
            continue

        batch_path = os.path.join(SQL_DIR, batch_file)
        with open(batch_path, 'r', encoding='utf-8') as f:
            sql = f.read()

        print(f"  [{i}/{total}] Executing {batch_file}...", end=" ", flush=True)
        try:
            execute_sql(sql)
            progress["db_batches_done"].append(batch_file)
            save_progress(progress)
            print("OK")
        except Exception as e:
            print(f"FAIL: {e}")
            return False

    print(f"  DB phase complete: {len(progress['db_batches_done'])}/{total} batches")
    return True


def phase_upload(progress):
    """Фаза 2: загрузка фото в Storage."""
    print("\n=== PHASE 2: Upload Photos ===")

    with open(MAPPING_FILE, 'r', encoding='utf-8') as f:
        mapping = json.load(f)
    with open(MANIFEST, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    total_files = 0
    uploaded = 0
    skipped = 0
    failed = 0

    for user_map, user_manifest in zip(mapping, manifest):
        auth_id = user_map['auth_user_id']
        folder_path = user_map['folder_path']
        user_key = f"{auth_id}"

        if user_key in progress.get("uploads_done", []):
            skipped += 1
            continue

        webp_base = os.path.join(WEBP_DIR, folder_path)
        user_ok = True

        # Upload avatar (if custom)
        if user_map['avatar_kind'] == 'custom':
            avatar_webp = os.path.join(webp_base, "avatar.webp")
            if os.path.exists(avatar_webp):
                storage_path = f"custom/{auth_id}/avatar.webp"
                total_files += 1
                if not upload_file("avatars", storage_path, avatar_webp):
                    user_ok = False
                    failed += 1
                else:
                    uploaded += 1

        # Upload album photos
        for photo_rec in user_map.get('photos', []):
            original = photo_rec['original_filename']
            webp_name = os.path.splitext(original)[0] + '.webp'
            webp_path = os.path.join(webp_base, webp_name)

            if os.path.exists(webp_path):
                storage_key = photo_rec['storage_key']
                total_files += 1
                if not upload_file("profile-photos", storage_key, webp_path):
                    user_ok = False
                    failed += 1
                else:
                    uploaded += 1

        if user_ok:
            progress.setdefault("uploads_done", []).append(user_key)
            save_progress(progress)

        # Progress log every 10 users
        idx = mapping.index(user_map)
        if (idx + 1) % 10 == 0:
            print(f"  [{idx+1}/{len(mapping)}] uploaded={uploaded} failed={failed}")

    print(f"\n  Upload phase complete: uploaded={uploaded}, skipped={skipped}, failed={failed}")
    return failed == 0


def main():
    print("=== Cold Start 2 Deploy ===")

    # Verify files exist
    for f in [MANIFEST, MAPPING_FILE]:
        if not os.path.exists(f):
            print(f"MISSING: {f}")
            sys.exit(1)

    progress = load_progress()

    # Phase 1: DB
    if not phase_db(progress):
        print("\nDB phase failed. Fix errors and re-run.")
        sys.exit(1)

    # Phase 2: Upload
    if not phase_upload(progress):
        print("\nSome uploads failed. Re-run to retry.")
        sys.exit(1)

    print("\n=== DEPLOY COMPLETE ===")


if __name__ == '__main__':
    main()
