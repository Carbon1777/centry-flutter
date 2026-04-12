#!/usr/bin/env python3
"""
TZ7 — Отбор лучшего фото для каждого места (v2 directory structure).
Фото: scraped_photos_v2/{city}/{yandex_id}/{1,2,3}.webp
Источник: yandex_parse_normalized.json
"""

import json
import sys
import time
import csv
from pathlib import Path
from collections import Counter

import cv2
import numpy as np

# --- Config ---
PHOTOS_BASE = Path(__file__).parent.parent / "scraped_photos_v2"
NORMALIZED_JSON = Path(__file__).parent / "yandex_parse_normalized.json"
OUTPUT_JSON = Path(__file__).parent / "photo_selection_v2_results.json"
OUTPUT_CSV = Path(__file__).parent / "photo_selection_v2_results.csv"
FACE_CASCADE_PATH = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

SMALL_FACE_RATIO = 0.05  # face width >= 5% = large (safety margin)


def detect_large_faces(img_bgr, cascade):
    h, w = img_bgr.shape[:2]
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    faces = cascade.detectMultiScale(
        gray, scaleFactor=1.1, minNeighbors=5,
        minSize=(int(w * 0.03), int(w * 0.03)),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )
    num_large = 0
    num_small = 0
    for (fx, fy, fw, fh) in faces:
        if fw / w >= SMALL_FACE_RATIO:
            num_large += 1
        else:
            num_small += 1
    return num_large > 0, num_large, num_small


def detect_timestamp_v2(img_bgr):
    h, w = img_bgr.shape[:2]
    y_start = int(h * 0.88)
    x_start = int(w * 0.65)
    region = img_bgr[y_start:, x_start:]
    if region.size == 0:
        return False
    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    rh, rw = gray.shape
    binary = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 21, 10
    )
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if len(contours) < 4:
        return False
    digit_candidates = []
    for c in contours:
        x, y, cw, ch = cv2.boundingRect(c)
        aspect = ch / max(cw, 1)
        area = cw * ch
        if 1.0 < aspect < 5.0 and 0.002 < (area / (rw * rh)) < 0.15 and ch > rh * 0.15:
            digit_candidates.append((x, y, cw, ch))
    if len(digit_candidates) < 4:
        return False
    digit_candidates.sort(key=lambda d: d[0])
    y_centers = [d[1] + d[3] / 2 for d in digit_candidates]
    heights = [d[3] for d in digit_candidates]
    if not heights:
        return False
    median_height = sorted(heights)[len(heights) // 2]
    median_y = sorted(y_centers)[len(y_centers) // 2]
    aligned = sum(1 for yc in y_centers if abs(yc - median_y) < median_height * 0.8)
    return aligned >= 6


def score_photo(img_bgr, file_size, index):
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    breakdown = {}
    score = 0.0

    # File size (+3)
    size_kb = file_size / 1024
    s = 3.0 if size_kb > 100 else 2.0 if size_kb > 60 else 1.0 if size_kb > 30 else 0.0
    score += s
    breakdown["file_size"] = s

    # Texture (+4) — Laplacian variance
    texture = float(np.var(cv2.Laplacian(gray, cv2.CV_64F)))
    s = 4.0 if texture > 3000 else 3.0 if texture > 2000 else 2.0 if texture > 1000 else 1.0 if texture > 500 else 0.0
    score += s
    breakdown["texture"] = s

    # Color diversity (+3)
    small = cv2.resize(img_bgr, (64, 64))
    small_hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
    h_bins = (small_hsv[:, :, 0] // 15).flatten()
    s_bins = (small_hsv[:, :, 1] // 85).flatten()
    combined = h_bins * 3 + s_bins
    diversity = min(len(set(combined)) / 36.0, 1.0) * 3.0
    score += diversity
    breakdown["color_diversity"] = round(diversity, 2)

    # Warm tones (+2)
    mean_hue = float(np.mean(hsv[:, :, 0]))
    s = 2.0 if 5 <= mean_hue <= 20 else 1.0 if 20 < mean_hue <= 30 else 0.0
    score += s
    breakdown["warm_tones"] = s

    # Brightness (+1)
    mean_val = float(np.mean(hsv[:, :, 2]))
    s = 1.0 if 80 <= mean_val <= 180 else 0.5 if 60 <= mean_val <= 200 else 0.0
    score += s
    breakdown["brightness"] = s

    # Contrast (+1.5)
    contrast = float(np.std(gray))
    s = 1.5 if contrast > 60 else 1.0 if contrast > 45 else 0.5 if contrast > 30 else 0.0
    score += s
    breakdown["contrast"] = s

    # Saturation (+1)
    mean_sat = float(np.mean(hsv[:, :, 1]))
    s = 1.0 if mean_sat > 50 else 0.5 if mean_sat > 30 else 0.0
    score += s
    breakdown["saturation"] = s

    # Timestamp penalty (-5)
    has_ts = detect_timestamp_v2(img_bgr)
    if has_ts:
        score -= 5.0
    breakdown["timestamp_penalty"] = -5.0 if has_ts else 0.0

    # Index 2 bonus (+0.5)
    s = 0.5 if index == 2 else 0.0
    score += s
    breakdown["index_bonus"] = s

    return round(score, 2), breakdown


def main():
    cascade = cv2.CascadeClassifier(FACE_CASCADE_PATH)
    if cascade.empty():
        print("ERROR: Haar cascade not found!")
        sys.exit(1)

    with open(NORMALIZED_JSON) as f:
        places = json.load(f)
    print(f"Loaded {len(places)} places from normalized JSON")

    results = []
    stats = Counter()
    t0 = time.time()

    for i, place in enumerate(places):
        yandex_id = place["yandex_id"]
        photo_paths = place.get("photo_paths", [])

        if (i + 1) % 1000 == 0:
            elapsed = time.time() - t0
            rate = (i + 1) / elapsed
            eta = (len(places) - i - 1) / rate
            print(f"  [{i+1}/{len(places)}] {rate:.1f} places/sec, ETA {eta:.0f}s")

        if not photo_paths:
            results.append({
                "yandex_id": yandex_id,
                "city": place["city"],
                "category": place["category"],
                "num_photos": 0,
                "selected_index": None,
                "selected_path": None,
                "needs_placeholder": True,
                "notes": "no_photos",
            })
            stats["no_photos"] += 1
            continue

        photo_data = []
        for rel_path in photo_paths:
            full_path = PHOTOS_BASE / rel_path
            # Extract index from filename: 1.webp, 2.webp, 3.webp
            index = int(full_path.stem)

            try:
                img = cv2.imread(str(full_path))
                if img is None:
                    photo_data.append({
                        "index": index, "path": rel_path,
                        "error": "cannot_read", "has_large_face": False, "score": -100,
                    })
                    stats["errors"] += 1
                    continue

                file_size = full_path.stat().st_size
                has_large_face, num_large, num_small = detect_large_faces(img, cascade)
                photo_score, breakdown = score_photo(img, file_size, index)
                has_timestamp = breakdown.get("timestamp_penalty", 0) < 0

                photo_data.append({
                    "index": index, "path": rel_path,
                    "has_large_face": bool(has_large_face),
                    "num_large_faces": int(num_large),
                    "num_small_faces": int(num_small),
                    "has_timestamp": bool(has_timestamp),
                    "score": photo_score,
                    "file_size": int(file_size),
                    "breakdown": breakdown,
                })
                if has_large_face:
                    stats["photos_with_faces"] += 1
                if has_timestamp:
                    stats["photos_with_timestamps"] += 1

            except Exception as e:
                photo_data.append({
                    "index": index, "path": rel_path,
                    "error": str(e), "has_large_face": False, "score": -100,
                })
                stats["errors"] += 1

        # Select best: exclude large faces, pick highest score
        safe = [p for p in photo_data if not p["has_large_face"] and p.get("score", -100) > -100]

        if safe:
            best = max(safe, key=lambda p: p["score"])
            selected_index = best["index"]
            selected_path = best["path"]
            needs_placeholder = False
        else:
            selected_index = None
            selected_path = None
            needs_placeholder = True
            stats["placeholder_needed"] += 1

        # Notes
        notes_parts = []
        if not safe and photo_data:
            all_faces = all(p.get("has_large_face") for p in photo_data if "error" not in p)
            if all_faces:
                notes_parts.append("all_photos_have_faces")
        face_photos = [p for p in photo_data if p.get("has_large_face")]
        if face_photos:
            notes_parts.append(f"faces_in_{','.join(str(p['index']) for p in face_photos)}")
        ts_photos = [p for p in photo_data if p.get("has_timestamp")]
        if ts_photos:
            notes_parts.append(f"timestamp_in_{','.join(str(p['index']) for p in ts_photos)}")

        results.append({
            "yandex_id": yandex_id,
            "city": place["city"],
            "category": place["category"],
            "num_photos": len(photo_paths),
            "selected_index": selected_index,
            "selected_path": selected_path,
            "needs_placeholder": needs_placeholder,
            "notes": "; ".join(notes_parts) if notes_parts else None,
            "photos": photo_data,
        })

        if selected_index:
            stats[f"selected_{selected_index}"] += 1

    elapsed = time.time() - t0
    print(f"\nDone in {elapsed:.1f}s ({len(places)/elapsed:.1f} places/sec)")
    print(f"\n=== RESULTS ===")
    print(f"Total places: {len(results)}")
    print(f"Selected photo 1: {stats.get('selected_1', 0)}")
    print(f"Selected photo 2: {stats.get('selected_2', 0)}")
    print(f"Selected photo 3: {stats.get('selected_3', 0)}")
    print(f"No photos at all: {stats.get('no_photos', 0)}")
    print(f"Placeholder needed (faces): {stats.get('placeholder_needed', 0)}")
    print(f"Photos with faces: {stats.get('photos_with_faces', 0)}")
    print(f"Photos with timestamps: {stats.get('photos_with_timestamps', 0)}")
    print(f"Read errors: {stats.get('errors', 0)}")

    # Save JSON
    class NpEncoder(json.JSONEncoder):
        def default(self, obj):
            if isinstance(obj, (np.bool_,)): return bool(obj)
            if isinstance(obj, (np.integer,)): return int(obj)
            if isinstance(obj, (np.floating,)): return float(obj)
            return super().default(obj)

    with open(OUTPUT_JSON, "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False, cls=NpEncoder)
    print(f"\nJSON: {OUTPUT_JSON}")

    # Save CSV
    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["yandex_id", "city", "category", "selected_index", "selected_path", "needs_placeholder", "notes"])
        for r in results:
            writer.writerow([
                r["yandex_id"], r["city"], r["category"],
                r["selected_index"] or "", r["selected_path"] or "",
                r["needs_placeholder"], r["notes"] or "",
            ])
    print(f"CSV: {OUTPUT_CSV}")

    # Per-city stats
    print(f"\n=== BY CITY ===")
    city_stats = {}
    for r in results:
        c = r["city"]
        if c not in city_stats:
            city_stats[c] = {"total": 0, "with_photo": 0, "placeholder": 0}
        city_stats[c]["total"] += 1
        if r["needs_placeholder"]:
            city_stats[c]["placeholder"] += 1
        else:
            city_stats[c]["with_photo"] += 1
    for city, s in sorted(city_stats.items(), key=lambda x: -x[1]["total"]):
        pct = s["with_photo"] / s["total"] * 100
        print(f"  {city}: {s['total']} total, {s['with_photo']} photo ({pct:.1f}%), {s['placeholder']} placeholder")


if __name__ == "__main__":
    main()
