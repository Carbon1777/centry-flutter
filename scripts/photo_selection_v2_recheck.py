#!/usr/bin/env python3
"""
TZ7 — Второй проход: перепроверка placeholder-кандидатов с более строгим детектором лиц.
Также: минимальный порог качества (score < 2 → placeholder).
"""

import json
import time
from pathlib import Path
from collections import Counter

import cv2
import numpy as np

PHOTOS_BASE = Path(__file__).parent.parent / "scraped_photos_v2"
SELECTION_JSON = Path(__file__).parent / "photo_selection_v2_results.json"
OUTPUT_JSON = Path(__file__).parent / "photo_selection_v2_final.json"
FACE_CASCADE_PATH = cv2.data.haarcascades + "haarcascade_frontalface_default.xml"

# Stricter thresholds for second pass
STRICT_FACE_RATIO = 0.08       # 8% width (was 5%)
STRICT_MIN_NEIGHBORS = 8       # (was 5)
MIN_QUALITY_SCORE = 2.0        # Below this → placeholder regardless


def strict_face_check(img_bgr, cascade):
    """Stricter face detection — fewer false positives."""
    h, w = img_bgr.shape[:2]
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)
    faces = cascade.detectMultiScale(
        gray,
        scaleFactor=1.1,
        minNeighbors=STRICT_MIN_NEIGHBORS,
        minSize=(int(w * 0.05), int(w * 0.05)),
        flags=cv2.CASCADE_SCALE_IMAGE,
    )
    for (fx, fy, fw, fh) in faces:
        if fw / w >= STRICT_FACE_RATIO:
            return True
    return False


def main():
    cascade = cv2.CascadeClassifier(FACE_CASCADE_PATH)
    if cascade.empty():
        print("ERROR: Haar cascade not found!")
        return

    with open(SELECTION_JSON) as f:
        data = json.load(f)

    # Separate: needs recheck vs already OK
    placeholders_with_photos = []
    ok_results = []
    no_photo_placeholders = []

    for r in data:
        if r['needs_placeholder'] and r['num_photos'] > 0:
            placeholders_with_photos.append(r)
        elif r['needs_placeholder'] and r['num_photos'] == 0:
            no_photo_placeholders.append(r)
        else:
            ok_results.append(r)

    print(f"OK results: {len(ok_results)}")
    print(f"Placeholders to recheck: {len(placeholders_with_photos)}")
    print(f"No-photo placeholders: {len(no_photo_placeholders)}")

    # Also apply min quality threshold to OK results
    quality_demoted = 0
    for r in ok_results:
        if r.get('selected_path'):
            safe = [p for p in r.get('photos', []) if not p.get('has_large_face') and p.get('score', -100) > -100]
            if safe:
                best_score = max(p['score'] for p in safe)
                if best_score < MIN_QUALITY_SCORE:
                    r['needs_placeholder'] = True
                    r['selected_path'] = None
                    r['selected_index'] = None
                    r['notes'] = (r.get('notes') or '') + '; low_quality_score'
                    quality_demoted += 1

    print(f"Demoted to placeholder (score < {MIN_QUALITY_SCORE}): {quality_demoted}")

    # Re-check placeholders with strict face detection
    recovered = 0
    still_placeholder = 0
    t0 = time.time()

    for i, r in enumerate(placeholders_with_photos):
        photos = r.get('photos', [])
        # Re-evaluate each photo with strict detection
        recheck_results = []

        for p in photos:
            if p.get('score', -100) <= -100:  # read error
                continue
            if p['score'] < MIN_QUALITY_SCORE:  # too low quality
                continue

            full_path = PHOTOS_BASE / p['path']
            if not full_path.exists():
                continue

            img = cv2.imread(str(full_path))
            if img is None:
                continue

            has_face_strict = strict_face_check(img, cascade)
            recheck_results.append({
                'index': p['index'],
                'path': p['path'],
                'score': p['score'],
                'has_face_strict': has_face_strict,
            })

        # Pick best photo that passes strict check
        safe_strict = [rc for rc in recheck_results if not rc['has_face_strict']]

        if safe_strict:
            best = max(safe_strict, key=lambda x: x['score'])
            r['needs_placeholder'] = False
            r['selected_index'] = best['index']
            r['selected_path'] = best['path']
            r['notes'] = (r.get('notes') or '') + '; recovered_strict_recheck'
            recovered += 1
        else:
            still_placeholder += 1

    elapsed = time.time() - t0
    print(f"\nRecheck done in {elapsed:.1f}s")
    print(f"Recovered from placeholder: {recovered}")
    print(f"Still placeholder: {still_placeholder}")

    # Merge all results
    final = ok_results + placeholders_with_photos + no_photo_placeholders
    # Sort by original order (yandex_id from normalized JSON)
    # Actually just keep them, order doesn't matter for the mapping

    # Stats
    total_placeholder = sum(1 for r in final if r['needs_placeholder'])
    total_with_photo = sum(1 for r in final if not r['needs_placeholder'])

    print(f"\n=== FINAL STATS ===")
    print(f"Total: {len(final)}")
    print(f"With photo: {total_with_photo} ({total_with_photo/len(final)*100:.1f}%)")
    print(f"Placeholder: {total_placeholder} ({total_placeholder/len(final)*100:.1f}%)")

    # By category
    print(f"\n=== BY CATEGORY ===")
    cat_stats = {}
    for r in final:
        cat = r['category']
        if cat not in cat_stats:
            cat_stats[cat] = {'total': 0, 'photo': 0, 'placeholder': 0}
        cat_stats[cat]['total'] += 1
        if r['needs_placeholder']:
            cat_stats[cat]['placeholder'] += 1
        else:
            cat_stats[cat]['photo'] += 1
    for cat, s in sorted(cat_stats.items(), key=lambda x: -x[1]['total']):
        pct = s['photo'] / s['total'] * 100
        print(f"  {cat}: {s['total']} total, {s['photo']} photo ({pct:.1f}%), {s['placeholder']} placeholder")

    # By city
    print(f"\n=== BY CITY ===")
    city_stats = {}
    for r in final:
        c = r['city']
        if c not in city_stats:
            city_stats[c] = {'total': 0, 'photo': 0, 'placeholder': 0}
        city_stats[c]['total'] += 1
        if r['needs_placeholder']:
            city_stats[c]['placeholder'] += 1
        else:
            city_stats[c]['photo'] += 1
    for city, s in sorted(city_stats.items(), key=lambda x: -x[1]['total']):
        pct = s['photo'] / s['total'] * 100
        print(f"  {city}: {s['total']} total, {s['photo']} photo ({pct:.1f}%), {s['placeholder']} placeholder")

    # Save
    class NpEncoder(json.JSONEncoder):
        def default(self, obj):
            if isinstance(obj, (np.bool_,)): return bool(obj)
            if isinstance(obj, (np.integer,)): return int(obj)
            if isinstance(obj, (np.floating,)): return float(obj)
            return super().default(obj)

    with open(OUTPUT_JSON, "w") as f:
        json.dump(final, f, indent=2, ensure_ascii=False, cls=NpEncoder)
    print(f"\nSaved: {OUTPUT_JSON}")


if __name__ == "__main__":
    main()
