#!/usr/bin/env python3
"""
Cold Start 2 — конвертация всех .jpg в .webp.
Аватарки: 512px по длинной стороне.
Альбомные фото: оригинальный размер.
"""

import os, json
from PIL import Image

BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
MANIFEST = os.path.join(BASE, "manifest.json")
WEBP_DIR = os.path.join(BASE, "webp")  # выходная папка

AVATAR_MAX_SIZE = 512


def convert_to_webp(src_path, dst_path, max_size=None, quality=85):
    """Конвертирует jpg в webp, опционально ресайзит."""
    with Image.open(src_path) as img:
        if img.mode in ('RGBA', 'P'):
            img = img.convert('RGB')

        if max_size:
            w, h = img.size
            if max(w, h) > max_size:
                ratio = max_size / max(w, h)
                new_w = int(w * ratio)
                new_h = int(h * ratio)
                img = img.resize((new_w, new_h), Image.LANCZOS)

        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        img.save(dst_path, 'WEBP', quality=quality)

        # Получаем итоговые размеры
        with Image.open(dst_path) as out:
            return out.size[0], out.size[1], os.path.getsize(dst_path)


def main():
    with open(MANIFEST, 'r', encoding='utf-8') as f:
        manifest = json.load(f)

    converted = 0
    skipped = 0
    errors = 0

    for user in manifest:
        user_path = os.path.join(BASE, user['city_slug'], user['district_slug'],
                                  user['team_slug'], user['folder_name'])

        # Выходная папка: webp/{city}/{district}/{team}/{folder}/
        out_dir = os.path.join(WEBP_DIR, user['city_slug'], user['district_slug'],
                               user['team_slug'], user['folder_name'])

        for photo in user['photos']:
            src = os.path.join(user_path, photo['filename'])
            webp_name = os.path.splitext(photo['filename'])[0] + '.webp'
            dst = os.path.join(out_dir, webp_name)

            if os.path.exists(dst):
                skipped += 1
                continue

            if not os.path.exists(src):
                print(f"  MISS: {src}")
                errors += 1
                continue

            try:
                is_avatar = photo['type'] == 'avatar'
                max_sz = AVATAR_MAX_SIZE if is_avatar else None
                w, h, sz = convert_to_webp(src, dst, max_size=max_sz)

                # Обновляем запись в манифесте с webp-размерами
                photo['webp_filename'] = webp_name
                photo['webp_width'] = w
                photo['webp_height'] = h
                photo['webp_size_bytes'] = sz

                converted += 1
            except Exception as e:
                print(f"  ERR: {src}: {e}")
                errors += 1

        # Для пользователей с системной аватаркой (avatar.webp) — копируем как есть
        if user['avatar_kind'] == 'system':
            system_avatar = os.path.join(user_path, 'avatar.webp')
            if os.path.exists(system_avatar):
                dst = os.path.join(out_dir, 'avatar.webp')
                if not os.path.exists(dst):
                    os.makedirs(out_dir, exist_ok=True)
                    import shutil
                    shutil.copy2(system_avatar, dst)
                    with Image.open(dst) as img:
                        w, h = img.size
                    # Добавляем в photos манифеста
                    user['photos'].append({
                        "filename": "avatar.webp",
                        "type": "system_avatar",
                        "width": w,
                        "height": h,
                        "size_bytes": os.path.getsize(dst),
                        "webp_filename": "avatar.webp",
                        "webp_width": w,
                        "webp_height": h,
                        "webp_size_bytes": os.path.getsize(dst),
                    })
                    converted += 1

    # Сохраняем обновлённый манифест
    with open(MANIFEST, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"\nКонвертация завершена:")
    print(f"  Конвертировано: {converted}")
    print(f"  Пропущено (уже есть): {skipped}")
    print(f"  Ошибки: {errors}")
    print(f"  Манифест обновлён: {MANIFEST}")


if __name__ == '__main__':
    main()
