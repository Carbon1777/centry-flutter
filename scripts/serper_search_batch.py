#!/usr/bin/env python3
"""
Batch Serper search for places without enrichment.
Results go ONLY to place_search_results_raw — no auto-enrichment.
"""
import json
import time
import sys
import os
import urllib.request
import ssl
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(__file__), '.env'))

SERPER_KEY = os.environ["SERPER_KEY"]
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_KEY"]

BATCH_LIMIT = 300
ssl_ctx = ssl.create_default_context()

def sb_fetch(path, method="GET", body=None):
    url = f"{SUPABASE_URL}{path}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, context=ssl_ctx) as resp:
        return json.loads(resp.read().decode())

def sb_post(path, body):
    url = f"{SUPABASE_URL}{path}"
    headers = {
        "apikey": SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    with urllib.request.urlopen(req, context=ssl_ctx) as resp:
        return resp.status

def serper_search(query):
    url = "https://google.serper.dev/search"
    headers = {
        "X-API-KEY": SERPER_KEY,
        "Content-Type": "application/json",
    }
    body = json.dumps({"q": query, "gl": "ru", "hl": "ru", "num": 5}).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, context=ssl_ctx) as resp:
        remaining = resp.headers.get("x-ratelimit-remaining", "?")
        data = json.loads(resp.read().decode())
        return data, remaining

def get_places_to_search(limit):
    """Get places from non-enriched cities"""
    query = (
        f"/rest/v1/rpc/get_places_for_serper_search"
    )
    # Use raw SQL via postgrest
    # Instead, fetch via REST with proper filters
    path = (
        f"/rest/v1/core_places?select=id,title,category,address,"
        f"area:core_areas(name,city:core_cities(name))"
        f"&order=title"
        f"&limit={limit}"
        # We'll filter in a different way
    )
    return sb_fetch(path)

def main():
    print(f"=== Serper Batch Search ({BATCH_LIMIT} places) ===\n")

    # Step 1: Get places to search via SQL RPC
    print("Fetching places without serper enrichment...")

    # Use PostgREST RPC to get places
    # Since complex joins are hard via REST, get IDs via SQL first
    sql_url = f"/rest/v1/rpc/get_places_for_serper_search"

    # Simpler approach: get all place IDs that have serper, then exclude
    # Actually let's just use a simpler query
    places_url = (
        f"/rest/v1/core_places?select=id,title,category,address,"
        f"area_id"
        f"&order=title&limit={BATCH_LIMIT}"
    )

    # Get areas with cities for city names
    areas = sb_fetch("/rest/v1/core_areas?select=id,name,city:core_cities(name)")
    area_map = {}
    for a in areas:
        city_name = a.get("city", {}).get("name", "") if a.get("city") else ""
        area_map[a["id"]] = city_name

    # Get places that already have serper enrichment
    enriched_ids = set()
    offset = 0
    while True:
        batch = sb_fetch(
            f"/rest/v1/place_enrichment?select=place_id&provider=eq.serper"
            f"&limit=1000&offset={offset}"
        )
        for r in batch:
            enriched_ids.add(r["place_id"])
        if len(batch) < 1000:
            break
        offset += 1000

    print(f"  Already enriched via serper: {len(enriched_ids)}")

    # Get places that already have search results
    searched_ids = set()
    offset = 0
    while True:
        batch = sb_fetch(
            f"/rest/v1/place_search_results_raw?select=place_id"
            f"&limit=1000&offset={offset}"
        )
        for r in batch:
            searched_ids.add(r["place_id"])
        if len(batch) < 1000:
            break
        offset += 1000

    print(f"  Already in search_results_raw: {len(searched_ids)}")

    skip_ids = enriched_ids | searched_ids

    # Get all places, filter locally
    all_places = []
    offset = 0
    while len(all_places) < BATCH_LIMIT + len(skip_ids):
        batch = sb_fetch(
            f"/rest/v1/core_places?select=id,title,category,address,area_id"
            f"&order=title&limit=1000&offset={offset}"
        )
        if not batch:
            break
        all_places.extend(batch)
        offset += 1000
        if len(batch) < 1000:
            break

    # Filter to only non-enriched, non-searched places
    # Prioritize non-MSK/SPb cities
    priority_places = []
    secondary_places = []

    for p in all_places:
        if p["id"] in skip_ids:
            continue
        city = area_map.get(p.get("area_id", ""), "")
        if city in ("Москва", "Санкт-Петербург"):
            secondary_places.append((p, city))
        else:
            priority_places.append((p, city))

    # Take priority (regional) first, then MSK/SPb
    to_search = priority_places[:BATCH_LIMIT]
    if len(to_search) < BATCH_LIMIT:
        to_search.extend(secondary_places[:BATCH_LIMIT - len(to_search)])

    print(f"  Places to search: {len(to_search)}")

    if not to_search:
        print("Nothing to search!")
        return

    # City distribution
    city_counts = {}
    for p, city in to_search:
        city_counts[city] = city_counts.get(city, 0) + 1
    print(f"  Distribution: {json.dumps(city_counts, ensure_ascii=False)}")

    # Step 2: Search each place
    print(f"\nStarting Serper search...\n")

    success = 0
    errors = 0

    for i, (place, city) in enumerate(to_search):
        query = f'"{place["title"]}" {city} {place["category"]} официальный сайт'

        try:
            data, remaining = serper_search(query)

            organic = data.get("organic", [])

            # Save results to place_search_results_raw
            rows = []
            for rank, result in enumerate(organic[:5], 1):
                rows.append({
                    "place_id": place["id"],
                    "query_text": query,
                    "provider": "serper",
                    "rank": rank,
                    "title": result.get("title", ""),
                    "snippet": result.get("snippet", ""),
                    "url": result.get("link", ""),
                    "raw": json.dumps(result),
                })

            if rows:
                sb_post("/rest/v1/place_search_results_raw", rows)

            success += 1
            city_short = city[:3] if city else "?"
            top_title = organic[0]["title"][:40] if organic else "no results"
            print(f"  [{i+1}/{len(to_search)}] {city_short} | {place['title'][:25]:25s} → {len(organic)} results | rem:{remaining} | {top_title}")

            # Rate limiting: ~2 req/sec to be safe
            time.sleep(0.5)

        except Exception as e:
            errors += 1
            print(f"  [{i+1}/{len(to_search)}] ERROR {place['title']}: {e}")
            time.sleep(1)

    print(f"\n=== Done: {success} ok, {errors} errors ===")

if __name__ == "__main__":
    main()
