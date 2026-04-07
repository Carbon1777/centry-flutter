#!/usr/bin/env python3
"""
TZ2_1 — Отбор лучшего фото для каждого места. v2
Детекция лиц, улучшенный скоринг (текстура, цветовое разнообразие, контраст),
исправленная детекция таймстампов.
"""

import os
import sys
import json
import re
import csv
import time
from pathlib import Path
from collections import Counter

import cv2
import numpy as np
from PIL import Image

# --- Config ---
PHOTOS_DIR = Path(__file__).parent.parent / "scraped_photos"
OUTPUT_JSON = Path(__file__).parent / "photo_selection_results.json"
OUTPUT_CSV = Path(__file__).parent / "photo_selection_results.csv"
FACE_CASCADE_PATH = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

# Face detection thresholds
LARGE_FACE_RATIO = 0.08   # face width > 8% of image width = large face
SMALL_FACE_RATIO = 0.05   # face width < 5% = background person, OK


def get_place_photos(photos_dir: Path) -> dict[str, list[tuple[int, Path]]]:
    """Scan directory and group photos by place_id."""
    places = {}
    for f in photos_dir.iterdir():
        if not f.suffix == ".webp":
            continue
        name = f.stem
        if name.endswith("_2"):
            place_id = name[:-2]
            index = 2
        elif name.endswith("_3"):
            place_id = name[:-2]
            index = 3
        else:
            place_id = name
            index = 1

        if place_id not in places:
            places[place_id] = []
        places[place_id].append((index, f))

    for pid in places:
        places[pid].sort(key=lambda x: x[0])

    return places


def detect_large_faces(img_bgr: np.ndarray, cascade: cv2.CascadeClassifier) -> tuple[bool, int, int]:
    """
    Detect faces in image.
    Large face = width > 8% of image width.
    Between 5-8% = counted as large (safety margin for legal risk).
    """
    h, w = img_bgr.shape[:2]
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)

    faces = cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=5,
        minSize=(int(w * 0.03), int(w * 0.03)),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )

    num_large = 0
    num_small = 0
    has_large = False

    for (fx, fy, fw, fh) in faces:
        ratio = fw / w
        if ratio >= SMALL_FACE_RATIO:
            num_large += 1
            has_large = True
        else:
            num_small += 1

    return has_large, num_large, num_small


def detect_timestamp_v2(img_bgr: np.ndarray) -> bool:
    """
    Improved timestamp detection. Look for actual digit-like contours
    in bottom-right corner, arranged horizontally.
    Much more specific than v1 edge-based heuristic.
    """
    h, w = img_bgr.shape[:2]
    # Bottom 12%, right 35% — typical timestamp placement
    y_start = int(h * 0.88)
    x_start = int(w * 0.65)
    region = img_bgr[y_start:, x_start:]

    if region.size == 0:
        return False

    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    rh, rw = gray.shape

    # Apply adaptive threshold to find text
    binary = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 21, 10
    )

    # Find contours
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if len(contours) < 4:
        return False  # Timestamps have at least 4 digits (year)

    # Filter contours that look like digits: small, roughly rectangular, similar height
    digit_candidates = []
    for c in contours:
        x, y, cw, ch = cv2.boundingRect(c)
        aspect = ch / max(cw, 1)
        area = cw * ch
        # Digits are taller than wide (aspect > 1), reasonable size
        if 1.0 < aspect < 5.0 and 0.002 < (area / (rw * rh)) < 0.15 and ch > rh * 0.15:
            digit_candidates.append((x, y, cw, ch))

    if len(digit_candidates) < 4:
        return False

    # Check if candidates are roughly aligned horizontally (similar y-center)
    digit_candidates.sort(key=lambda d: d[0])  # sort by x
    y_centers = [d[1] + d[3] / 2 for d in digit_candidates]
    heights = [d[3] for d in digit_candidates]

    if not heights:
        return False

    median_height = sorted(heights)[len(heights) // 2]
    median_y = sorted(y_centers)[len(y_centers) // 2]

    # Count digits on the same horizontal line (within 1 height tolerance)
    aligned = sum(1 for yc in y_centers if abs(yc - median_y) < median_height * 0.8)

    # Need at least 6 aligned characters for a date pattern (e.g., 2020/9/29)
    return aligned >= 6


def compute_texture_score(gray: np.ndarray) -> float:
    """
    Laplacian variance — measures detail/texture level.
    Interiors: lots of texture (furniture, decor, patterns) → high variance.
    Facades: smoother surfaces (walls, sky) → lower variance.
    """
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    return float(np.var(lap))


def compute_color_diversity(img_bgr: np.ndarray) -> float:
    """
    Count distinct color clusters (approximate).
    Interiors have more color variety than facades.
    Returns 0-1 normalized score.
    """
    # Resize for speed
    small = cv2.resize(img_bgr, (64, 64))
    hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)

    # Quantize hue into 12 bins, saturation into 3
    h_bins = (hsv[:, :, 0] // 15).flatten()  # 12 bins
    s_bins = (hsv[:, :, 1] // 85).flatten()  # 3 bins
    combined = h_bins * 3 + s_bins  # 36 possible bins

    unique_bins = len(set(combined))
    return min(unique_bins / 36.0, 1.0)  # Normalize to 0-1


def compute_contrast(gray: np.ndarray) -> float:
    """Standard deviation of pixel intensities. Higher = more contrast."""
    return float(np.std(gray))


def score_photo_v2(img_bgr: np.ndarray, file_size: int, index: int) -> tuple[float, dict]:
    """
    Improved scoring with texture analysis, color diversity, contrast.
    Returns (total_score, breakdown_dict).
    """
    h, w = img_bgr.shape[:2]
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)

    breakdown = {}
    score = 0.0

    # 1. File size (+3 max) — larger = more detail
    size_kb = file_size / 1024
    if size_kb > 100:
        s = 3.0
    elif size_kb > 60:
        s = 2.0
    elif size_kb > 30:
        s = 1.0
    else:
        s = 0.0
    score += s
    breakdown["file_size"] = s

    # 2. Texture/detail score (+4 max) — KEY differentiator for interiors
    texture = compute_texture_score(gray)
    # Typical range: 200-2000 for facades, 1000-5000+ for interiors
    if texture > 3000:
        s = 4.0
    elif texture > 2000:
        s = 3.0
    elif texture > 1000:
        s = 2.0
    elif texture > 500:
        s = 1.0
    else:
        s = 0.0
    score += s
    breakdown["texture"] = s

    # 3. Color diversity (+3 max) — interiors have richer colors
    diversity = compute_color_diversity(img_bgr)
    s = diversity * 3.0
    score += s
    breakdown["color_diversity"] = round(s, 2)

    # 4. Warm tones (+2 max) — warm lighting = interior
    mean_hue = float(np.mean(hsv[:, :, 0]))  # 0-180 in OpenCV
    if 5 <= mean_hue <= 20:  # 10-40° real hue
        s = 2.0
    elif 20 < mean_hue <= 30:
        s = 1.0
    else:
        s = 0.0
    score += s
    breakdown["warm_tones"] = s

    # 5. Brightness — medium preferred (+1 max)
    mean_val = float(np.mean(hsv[:, :, 2]))
    if 80 <= mean_val <= 180:
        s = 1.0
    elif 60 <= mean_val <= 200:
        s = 0.5
    else:
        s = 0.0
    score += s
    breakdown["brightness"] = s

    # 6. Contrast (+1.5 max) — good contrast = visually appealing
    contrast = compute_contrast(gray)
    if contrast > 60:
        s = 1.5
    elif contrast > 45:
        s = 1.0
    elif contrast > 30:
        s = 0.5
    else:
        s = 0.0
    score += s
    breakdown["contrast"] = s

    # 7. Saturation (+1 max)
    mean_sat = float(np.mean(hsv[:, :, 1]))
    if mean_sat > 50:
        s = 1.0
    elif mean_sat > 30:
        s = 0.5
    else:
        s = 0.0
    score += s
    breakdown["saturation"] = s

    # 8. Timestamp penalty (-5) — improved detection
    has_ts = detect_timestamp_v2(img_bgr)
    if has_ts:
        score -= 5.0
    breakdown["timestamp_penalty"] = -5.0 if has_ts else 0.0

    # 9. Index bonus — Yandex often puts interior as photo 2
    if index == 2:
        s = 0.5
    else:
        s = 0.0
    score += s
    breakdown["index_bonus"] = s

    return round(score, 2), breakdown


def process_all_places(photos_dir: Path) -> list[dict]:
    """Main processing loop."""
    cascade = cv2.CascadeClassifier(FACE_CASCADE_PATH)
    if cascade.empty():
        print("ERROR: Could not load Haar cascade!")
        sys.exit(1)

    places = get_place_photos(photos_dir)
    print(f"Found {len(places)} places with photos")

    results = []
    stats = Counter()
    t0 = time.time()

    for i, (place_id, photos) in enumerate(places.items()):
        if (i + 1) % 500 == 0:
            elapsed = time.time() - t0
            rate = (i + 1) / elapsed
            eta = (len(places) - i - 1) / rate
            print(f"  [{i+1}/{len(places)}] {rate:.1f} places/sec, ETA {eta:.0f}s")

        photo_data = []
        for index, path in photos:
            try:
                img = cv2.imread(str(path))
                if img is None:
                    photo_data.append({
                        "index": index,
                        "path": str(path.name),
                        "error": "cannot_read",
                        "has_large_face": False,
                        "score": -100,
                    })
                    stats["errors"] += 1
                    continue

                file_size = path.stat().st_size
                has_large_face, num_large, num_small = detect_large_faces(img, cascade)
                photo_score, breakdown = score_photo_v2(img, file_size, index)
                has_timestamp = breakdown.get("timestamp_penalty", 0) < 0

                photo_data.append({
                    "index": index,
                    "path": str(path.name),
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
                    "index": index,
                    "path": str(path.name),
                    "error": str(e),
                    "has_large_face": False,
                    "score": -100,
                })
                stats["errors"] += 1

        # Select best photo: filter out large faces, pick highest score
        safe_photos = [p for p in photo_data if not p["has_large_face"] and p.get("score", -100) > -100]

        if safe_photos:
            best = max(safe_photos, key=lambda p: p["score"])
            selected_index = best["index"]
            needs_placeholder = False
            all_faces = False
        elif photo_data:
            selected_index = None
            needs_placeholder = True
            all_faces = all(p.get("has_large_face", False) for p in photo_data if "error" not in p)
            stats["placeholder_needed"] += 1
        else:
            selected_index = None
            needs_placeholder = True
            all_faces = False
            stats["placeholder_needed"] += 1

        # Build photo path
        if selected_index == 1:
            selected_path = f"scraped_photos/{place_id}.webp"
        elif selected_index:
            selected_path = f"scraped_photos/{place_id}_{selected_index}.webp"
        else:
            selected_path = None

        # Notes
        notes_parts = []
        if all_faces:
            notes_parts.append("all_photos_have_faces")
        face_photos = [p for p in photo_data if p.get("has_large_face")]
        if face_photos:
            notes_parts.append(f"faces_in_photo_{'_'.join(str(p['index']) for p in face_photos)}")
        ts_photos = [p for p in photo_data if p.get("has_timestamp")]
        if ts_photos:
            notes_parts.append(f"timestamp_in_photo_{'_'.join(str(p['index']) for p in ts_photos)}")
        error_photos = [p for p in photo_data if "error" in p]
        if error_photos:
            notes_parts.append(f"error_in_photo_{'_'.join(str(p['index']) for p in error_photos)}")

        result = {
            "place_id": place_id,
            "num_photos": len(photos),
            "selected_index": selected_index,
            "selected_path": selected_path,
            "needs_placeholder": needs_placeholder,
            "notes": "; ".join(notes_parts) if notes_parts else None,
            "photos": photo_data,
        }
        results.append(result)

        if selected_index:
            stats[f"selected_{selected_index}"] += 1
        if selected_index and len(photos) > 1 and selected_index != 1:
            stats["changed_from_1"] += 1

    elapsed = time.time() - t0
    print(f"\nDone in {elapsed:.1f}s ({len(places)/elapsed:.1f} places/sec)")

    print(f"\n=== RESULTS v2 ===")
    print(f"Total places: {len(results)}")
    print(f"Selected photo 1: {stats.get('selected_1', 0)}")
    print(f"Selected photo 2: {stats.get('selected_2', 0)}")
    print(f"Selected photo 3: {stats.get('selected_3', 0)}")
    print(f"Changed from default (1): {stats.get('changed_from_1', 0)}")
    print(f"Placeholder needed (all faces): {stats.get('placeholder_needed', 0)}")
    print(f"Photos with faces detected: {stats.get('photos_with_faces', 0)}")
    print(f"Photos with timestamps: {stats.get('photos_with_timestamps', 0)}")
    print(f"Read errors: {stats.get('errors', 0)}")

    return results


class NumpyEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (np.bool_,)):
            return bool(obj)
        if isinstance(obj, (np.integer,)):
            return int(obj)
        if isinstance(obj, (np.floating,)):
            return float(obj)
        return super().default(obj)


def save_results(results: list[dict]):
    """Save results to JSON and CSV."""
    with open(OUTPUT_JSON, "w") as f:
        json.dump(results, f, indent=2, ensure_ascii=False, cls=NumpyEncoder)
    print(f"\nJSON saved: {OUTPUT_JSON}")

    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["place_id", "selected_photo_index", "selected_photo_path", "photo_needs_placeholder", "notes"])
        for r in results:
            writer.writerow([
                r["place_id"],
                r["selected_index"] if r["selected_index"] else "",
                r["selected_path"] if r["selected_path"] else "",
                r["needs_placeholder"],
                r["notes"] if r["notes"] else "",
            ])
    print(f"CSV saved: {OUTPUT_CSV}")


if __name__ == "__main__":
    if not PHOTOS_DIR.exists():
        print(f"ERROR: Photos directory not found: {PHOTOS_DIR}")
        sys.exit(1)

    results = process_all_places(PHOTOS_DIR)
    save_results(results)
