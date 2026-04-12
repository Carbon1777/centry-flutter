#!/usr/bin/env python3
"""TZ8: Upload normalized places + photo mapping to staging_places_v2 via Supabase REST API."""

import json
import os

# Load .env manually
with open("scripts/.env") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ[k] = v

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
BATCH_SIZE = 200

def load_data():
    with open("scripts/yandex_parse_normalized.json") as f:
        places = json.load(f)
    with open("scripts/photo_mapping_v2.json") as f:
        photos = json.load(f)

    photo_map = {p["yandex_id"]: p for p in photos}

    rows = []
    for p in places:
        yid = p["yandex_id"]
        pm = photo_map.get(yid, {})
        rows.append({
            "yandex_id": yid,
            "title": p["title"],
            "address": p["address"],
            "category": p["category"],
            "city": p["city"],
            "area_name": p.get("area_name"),
            "phone": p.get("phone"),
            "phones_all": p.get("phones_all", []),
            "website": p.get("website"),
            "rating": p.get("rating"),
            "review_count": p.get("review_count"),
            "lat": p["lat"],
            "lng": p["lng"],
            "storage_key": pm.get("storage_key", ""),
            "is_placeholder": pm.get("is_placeholder", True),
        })

    print(f"Prepared {len(rows)} rows")
    return rows


def main():
    from supabase import create_client
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

    rows = load_data()
    total = len(rows)
    batches = [rows[i:i+BATCH_SIZE] for i in range(0, total, BATCH_SIZE)]

    print(f"Uploading {total} rows in {len(batches)} batches of {BATCH_SIZE}")

    uploaded = 0
    for i, batch in enumerate(batches):
        try:
            result = supabase.table("staging_places_v2").upsert(batch, on_conflict="yandex_id").execute()
            uploaded += len(batch)
            if (i + 1) % 10 == 0 or i == len(batches) - 1:
                print(f"  Batch {i+1}/{len(batches)} done — {uploaded}/{total} uploaded")
        except Exception as e:
            print(f"  ERROR on batch {i+1}: {e}")
            # Try row by row for this batch
            for row in batch:
                try:
                    supabase.table("staging_places_v2").upsert(row, on_conflict="yandex_id").execute()
                    uploaded += 1
                except Exception as e2:
                    print(f"    SKIP {row['yandex_id']}: {e2}")

    print(f"\nDone: {uploaded}/{total} rows uploaded to staging_places_v2")


if __name__ == "__main__":
    main()
