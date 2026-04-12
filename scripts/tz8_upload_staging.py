#!/usr/bin/env python3
"""TZ8: Upload normalized places + photo mapping to staging_places_v2 via Supabase REST API."""

import json
import os
import subprocess
import sys

BATCH_SIZE = 100
PROJECT_ID = "lqgzvolirohuettizkhx"

def load_data():
    with open("scripts/yandex_parse_normalized.json") as f:
        places = json.load(f)
    with open("scripts/photo_mapping_v2.json") as f:
        photos = json.load(f)

    photo_map = {p["yandex_id"]: p for p in photos}

    # Merge photo info into places
    for place in places:
        yid = place["yandex_id"]
        pm = photo_map.get(yid, {})
        place["storage_key"] = pm.get("storage_key", "")
        place["is_placeholder"] = pm.get("is_placeholder", True)

    print(f"Loaded {len(places)} places, {len(photo_map)} photo mappings")
    missing_photos = [p for p in places if not p["storage_key"]]
    if missing_photos:
        print(f"WARNING: {len(missing_photos)} places without photo mapping")

    return places


def escape_sql(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def build_insert_batch(batch):
    rows = []
    for p in batch:
        phones_all = json.dumps(p.get("phones_all", []))
        row = (
            f"({escape_sql(p['yandex_id'])}, {escape_sql(p['title'])}, "
            f"{escape_sql(p['address'])}, {escape_sql(p['category'])}, "
            f"{escape_sql(p['city'])}, {escape_sql(p.get('area_name'))}, "
            f"{escape_sql(p.get('phone'))}, {escape_sql(phones_all)}::jsonb, "
            f"{escape_sql(p.get('website'))}, {p.get('rating', 'NULL')}, "
            f"{p.get('review_count', 'NULL')}, {p['lat']}, {p['lng']}, "
            f"{escape_sql(p.get('storage_key'))}, {str(p.get('is_placeholder', False)).lower()})"
        )
        rows.append(row)

    sql = (
        "INSERT INTO staging_places_v2 "
        "(yandex_id, title, address, category, city, area_name, phone, phones_all, "
        "website, rating, review_count, lat, lng, storage_key, is_placeholder) VALUES\n"
        + ",\n".join(rows)
        + "\nON CONFLICT (yandex_id) DO NOTHING;"
    )
    return sql


def main():
    places = load_data()

    total = len(places)
    batches = [places[i:i+BATCH_SIZE] for i in range(0, total, BATCH_SIZE)]

    print(f"Uploading {total} places in {len(batches)} batches of {BATCH_SIZE}")

    for i, batch in enumerate(batches):
        sql = build_insert_batch(batch)
        # Write SQL to temp file and read it back for the MCP call
        with open(f"/tmp/tz8_batch_{i}.sql", "w") as f:
            f.write(sql)

        print(f"  Batch {i+1}/{len(batches)} ({len(batch)} rows) - written to /tmp/tz8_batch_{i}.sql")

    print(f"\nAll {len(batches)} batch files written to /tmp/tz8_batch_*.sql")
    print("Use execute_batches.py to run them against Supabase")


if __name__ == "__main__":
    main()
