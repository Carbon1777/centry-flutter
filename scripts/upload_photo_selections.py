#!/usr/bin/env python3
"""Upload photo selection results to Supabase via RPC."""

import json
import os
import httpx
from pathlib import Path
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
RESULTS_FILE = Path(__file__).parent / "photo_selection_results.json"
BATCH_SIZE = 500

def main():
    with open(RESULTS_FILE) as f:
        data = json.load(f)

    # Build compact payload
    payload = []
    for r in data:
        item = {
            "p": r["place_id"],
            "i": r["selected_index"],
            "s": r["selected_path"],
            "f": r["needs_placeholder"],
            "n": r["notes"],
        }
        payload.append(item)

    print(f"Total records: {len(payload)}")

    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }

    total_updated = 0
    with httpx.Client(timeout=60) as client:
        for i in range(0, len(payload), BATCH_SIZE):
            batch = payload[i:i + BATCH_SIZE]
            resp = client.post(
                f"{SUPABASE_URL}/rest/v1/rpc/update_photo_selections",
                headers=headers,
                json={"data": batch},
            )
            if resp.status_code != 200:
                print(f"ERROR batch {i//BATCH_SIZE}: {resp.status_code} {resp.text[:500]}")
                continue

            updated = resp.json()
            total_updated += updated
            print(f"  Batch {i//BATCH_SIZE}: {updated} rows updated (total: {total_updated})")

    print(f"\nDone. Total updated: {total_updated}")


if __name__ == "__main__":
    main()
