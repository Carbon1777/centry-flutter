#!/usr/bin/env python3
"""
Cold Start 2 — загрузка фото в Supabase Storage.
Аватары → bucket 'avatars', путь custom/{auth_user_id}/avatar.webp
Альбомные фото → bucket 'profile-photos', путь {storage_key}
"""

import os, sys, json, urllib.request, urllib.error

BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
WEBP_DIR = os.path.join(BASE, "webp")
MAPPING_FILE = os.path.join(BASE, "user_mapping.json")
MANIFEST_FILE = os.path.join(BASE, "manifest.json")
PROGRESS_FILE = os.path.join(BASE, "upload_progress.json")

SUPABASE_URL = "https://lqgzvolirohuettizkhx.supabase.co"
SERVICE_KEY = "SUPABASE_SERVICE_KEY_REDACTED"


def load_progress():
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {"done": []}


def save_progress(progress):
    with open(PROGRESS_FILE, 'w') as f:
        json.dump(progress, f)


def upload_file(bucket, path, filepath):
    """Upload file to Supabase Storage."""
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}"
    with open(filepath, 'rb') as f:
        data = f.read()

    req = urllib.request.Request(url, data=data, method='POST', headers={
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "image/webp",
        "apikey": SERVICE_KEY,
        "x-upsert": "true",
    })
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        return True, ""
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        return False, f"HTTP {e.code}: {body[:200]}"
    except Exception as e:
        return False, str(e)


def main():
    with open(MAPPING_FILE) as f:
        mapping = json.load(f)
    with open(MANIFEST_FILE) as f:
        manifest = json.load(f)

    progress = load_progress()
    done_set = set(progress["done"])

    uploaded = 0
    skipped = 0
    failed = 0
    total_users = len(mapping)

    for i, (user_map, user_man) in enumerate(zip(mapping, manifest)):
        auth_id = user_map['auth_user_id']
        folder_path = user_map['folder_path']

        if auth_id in done_set:
            skipped += 1
            continue

        webp_base = os.path.join(WEBP_DIR, folder_path)
        user_ok = True

        # 1. Upload avatar (custom only)
        if user_map['avatar_kind'] == 'custom':
            avatar_webp = os.path.join(webp_base, "avatar.webp")
            if os.path.exists(avatar_webp):
                storage_path = f"custom/{auth_id}/avatar.webp"
                ok, err = upload_file("avatars", storage_path, avatar_webp)
                if ok:
                    uploaded += 1
                else:
                    print(f"  FAIL avatar {folder_path}: {err}")
                    user_ok = False
                    failed += 1

        # 2. Upload album photos
        for photo_rec in user_map.get('photos', []):
            original = photo_rec['original_filename']
            webp_name = os.path.splitext(original)[0] + '.webp'
            webp_path = os.path.join(webp_base, webp_name)

            if os.path.exists(webp_path):
                storage_key = photo_rec['storage_key']
                ok, err = upload_file("profile-photos", storage_key, webp_path)
                if ok:
                    uploaded += 1
                else:
                    print(f"  FAIL photo {folder_path}/{webp_name}: {err}")
                    user_ok = False
                    failed += 1

        if user_ok:
            progress["done"].append(auth_id)
            done_set.add(auth_id)

        # Save progress every 10 users
        if (i + 1) % 10 == 0:
            save_progress(progress)
            print(f"  [{i+1}/{total_users}] uploaded={uploaded} skipped={skipped} failed={failed}")

    save_progress(progress)
    print(f"\n=== Upload complete: uploaded={uploaded}, skipped={skipped}, failed={failed} ===")


if __name__ == '__main__':
    main()
