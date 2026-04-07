#!/usr/bin/env python3
"""
TZ3: Постобработка фото (резкость + насыщенность) и загрузка на Supabase Storage.
- Читает selected_photo_path из staging_places_normalized
- Применяет лёгкую обработку (sharpness +8%, saturation +7%)
- Загружает в brand-media/scraped_photos/{place_id}.webp
"""

import os
import sys
import json
import time
import io
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

from PIL import Image, ImageEnhance
from supabase import create_client

# --- Config ---
BATCH_SIZE = 20
PAUSE_BETWEEN_BATCHES = 0.5  # seconds
SHARPNESS_FACTOR = 1.08      # +8%
SATURATION_FACTOR = 1.07     # +7%
BUCKET = "brand-media"
STORAGE_PREFIX = "scraped_photos"
PHOTOS_DIR = Path(__file__).parent.parent / "scraped_photos"

# --- Load env ---
from dotenv import load_dotenv
load_dotenv(Path(__file__).parent / ".env")

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

supabase = create_client(SUPABASE_URL, SUPABASE_KEY)


def process_image(input_path: Path) -> bytes:
    """Apply slight sharpness and saturation enhancement, return webp bytes."""
    img = Image.open(input_path).convert("RGB")

    # Sharpness
    img = ImageEnhance.Sharpness(img).enhance(SHARPNESS_FACTOR)
    # Saturation
    img = ImageEnhance.Color(img).enhance(SATURATION_FACTOR)

    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=82)
    return buf.getvalue()


def upload_photo(place_id: str, local_path: str) -> dict:
    """Process and upload a single photo. Returns status dict."""
    full_path = PHOTOS_DIR.parent / local_path

    if not full_path.exists():
        return {"place_id": place_id, "status": "missing", "error": f"File not found: {full_path}"}

    try:
        processed_bytes = process_image(full_path)
        storage_key = f"{STORAGE_PREFIX}/{place_id}.webp"

        # Upload (upsert)
        supabase.storage.from_(BUCKET).upload(
            path=storage_key,
            file=processed_bytes,
            file_options={"content-type": "image/webp", "upsert": "true"}
        )

        return {"place_id": place_id, "status": "ok", "size": len(processed_bytes)}
    except Exception as e:
        return {"place_id": place_id, "status": "error", "error": str(e)}


def fetch_all_places():
    """Fetch all places with pagination (supabase default limit is 1000)."""
    all_places = []
    page_size = 1000
    offset = 0
    while True:
        result = supabase.table("staging_places_normalized").select(
            "place_id, selected_photo_path"
        ).eq(
            "processing_status", "processed"
        ).eq(
            "photo_needs_placeholder", False
        ).not_.is_("selected_photo_path", "null").range(offset, offset + page_size - 1).execute()

        batch = result.data
        all_places.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size
    return all_places


def main():
    print("Fetching places from staging_places_normalized...")
    places = fetch_all_places()
    print(f"Found {len(places)} places with photos to upload")

    # Optional: resume from where we left off
    log_file = Path(__file__).parent / "upload_log.json"
    uploaded_ids = set()
    if log_file.exists():
        with open(log_file) as f:
            for line in f:
                entry = json.loads(line)
                if entry.get("status") == "ok":
                    uploaded_ids.add(entry["place_id"])
        print(f"Resuming: {len(uploaded_ids)} already uploaded")

    remaining = [p for p in places if p["place_id"] not in uploaded_ids]
    print(f"Remaining to upload: {len(remaining)}")

    stats = {"ok": 0, "error": 0, "missing": 0}

    with open(log_file, "a") as log:
        for batch_start in range(0, len(remaining), BATCH_SIZE):
            batch = remaining[batch_start:batch_start + BATCH_SIZE]

            with ThreadPoolExecutor(max_workers=BATCH_SIZE) as executor:
                futures = {
                    executor.submit(upload_photo, p["place_id"], p["selected_photo_path"]): p
                    for p in batch
                }

                for future in as_completed(futures):
                    result = future.result()
                    stats[result["status"]] = stats.get(result["status"], 0) + 1
                    log.write(json.dumps(result) + "\n")

                    if result["status"] != "ok":
                        print(f"  [{result['status']}] {result['place_id']}: {result.get('error', '')}")

            total_done = batch_start + len(batch)
            if total_done % 200 == 0 or total_done == len(remaining):
                print(f"Progress: {total_done}/{len(remaining)} | ok={stats['ok']} err={stats['error']} miss={stats['missing']}")

            log.flush()
            time.sleep(PAUSE_BETWEEN_BATCHES)

    print(f"\nDone! ok={stats['ok']}, error={stats['error']}, missing={stats['missing']}")


if __name__ == "__main__":
    main()
