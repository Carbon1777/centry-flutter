#!/usr/bin/env python3
"""
TZ7 — Загрузка отобранных фото на Supabase Storage.
Читает photo_selection_v2_results.json, загружает в brand-media/scraped_photos_v2/{yandex_id}.webp.
Фото уже обработаны при скачивании — постобработка не нужна.
Resume через upload_log_v2.json.
"""

import os
import json
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

from supabase import create_client
from dotenv import load_dotenv

# --- Config ---
BATCH_SIZE = 1
PAUSE_BETWEEN_BATCHES = 1.5
BUCKET = "brand-media"
STORAGE_PREFIX = "scraped_photos_v2"
PHOTOS_BASE = Path(__file__).parent.parent / "scraped_photos_v2"
SELECTION_JSON = Path(__file__).parent / "photo_selection_v2_final.json"
LOG_FILE = Path(__file__).parent / "upload_log_v2.json"

load_dotenv(Path(__file__).parent / ".env")
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def upload_photo(yandex_id: str, selected_path: str) -> dict:
    """Read file and upload to Storage. No post-processing needed."""
    full_path = PHOTOS_BASE / selected_path
    if not full_path.exists():
        return {"yandex_id": yandex_id, "status": "missing", "error": f"Not found: {full_path}"}

    try:
        data = full_path.read_bytes()
        storage_key = f"{STORAGE_PREFIX}/{yandex_id}.webp"

        supabase.storage.from_(BUCKET).upload(
            path=storage_key,
            file=data,
            file_options={"content-type": "image/webp", "upsert": "true"}
        )
        return {"yandex_id": yandex_id, "status": "ok", "size": len(data), "storage_key": storage_key}
    except Exception as e:
        return {"yandex_id": yandex_id, "status": "error", "error": str(e)}


def main():
    with open(SELECTION_JSON) as f:
        results = json.load(f)

    # Only places with selected photos (not placeholders)
    to_upload = [r for r in results if r.get("selected_path") and not r.get("needs_placeholder")]
    print(f"Total places: {len(results)}, with photo to upload: {len(to_upload)}")

    # Resume
    uploaded_ids = set()
    if LOG_FILE.exists():
        with open(LOG_FILE) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("status") == "ok":
                    uploaded_ids.add(entry["yandex_id"])
        print(f"Already uploaded: {len(uploaded_ids)}")

    remaining = [r for r in to_upload if r["yandex_id"] not in uploaded_ids]
    print(f"Remaining: {len(remaining)}")

    if not remaining:
        print("Nothing to upload!")
        return

    stats = {"ok": 0, "error": 0, "missing": 0}

    with open(LOG_FILE, "a") as log:
        for batch_start in range(0, len(remaining), BATCH_SIZE):
            batch = remaining[batch_start:batch_start + BATCH_SIZE]

            with ThreadPoolExecutor(max_workers=BATCH_SIZE) as executor:
                # selected_path is relative to city dir, e.g. "moscow/132720534766/2.webp"
                futures = {
                    executor.submit(upload_photo, r["yandex_id"], r["selected_path"]): r
                    for r in batch
                }
                for future in as_completed(futures):
                    result = future.result()
                    stats[result["status"]] = stats.get(result["status"], 0) + 1
                    log.write(json.dumps(result) + "\n")
                    if result["status"] != "ok":
                        print(f"  [{result['status']}] {result['yandex_id']}: {result.get('error', '')}")

            total_done = batch_start + len(batch)
            if total_done % 200 == 0 or total_done == len(remaining):
                print(f"Progress: {total_done}/{len(remaining)} | ok={stats['ok']} err={stats['error']} miss={stats['missing']}")

            log.flush()
            time.sleep(PAUSE_BETWEEN_BATCHES)

    print(f"\nDone! ok={stats['ok']}, error={stats['error']}, missing={stats['missing']}")


if __name__ == "__main__":
    main()
