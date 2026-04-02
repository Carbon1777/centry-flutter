#!/usr/bin/env python3
"""
Cold Start 2 — генерация manifest.json для 250 пользователей.

Сканирует папку cold_start2/, собирает данные из имён папок и файлов,
генерирует рандомные возраст и предпочтения.
"""

import os, json, random, re
from PIL import Image

BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
OUTPUT = "/Users/jcat/Documents/Doc/Projects/cold_start2/manifest.json"

REST_PREFERENCES = [
    "rest_format_leisure", "rest_format_dining", "rest_format_loud",
    "rest_format_spontaneous", "rest_format_walks",
    "rest_format_active", "rest_format_bars",
]

REST_DISLIKES = [
    "rest_dislike_long_walks", "rest_dislike_large_groups",
    "rest_dislike_spontaneous", "rest_dislike_late",
    "rest_dislike_strict_plans",
]

CITY_DISPLAY = {
    "moskva": "Москва",
    "sankt_peterburg": "Санкт-Петербург",
}

random.seed(42)  # воспроизводимость


def parse_folder_name(folder_name):
    """Парсит имя папки вида 'hawk9_w (Настя)' -> nickname, gender, display_name."""
    # Ищем паттерн: nickname_m/w (Имя)
    m = re.match(r'^(.+?)_(m|w)\s*\((.+?)\)$', folder_name)
    if m:
        return m.group(1), m.group(2), m.group(3)
    # Fallback: пробуем без скобок
    m = re.match(r'^(.+?)_(m|w)$', folder_name)
    if m:
        return m.group(1), m.group(2), m.group(1)
    return folder_name, 'unknown', folder_name


def get_photo_info(filepath):
    """Получает размеры и размер файла фото."""
    try:
        size_bytes = os.path.getsize(filepath)
        with Image.open(filepath) as img:
            w, h = img.size
        return {"width": w, "height": h, "size_bytes": size_bytes}
    except Exception as e:
        print(f"  WARN: cannot read {filepath}: {e}")
        return {"width": 0, "height": 0, "size_bytes": os.path.getsize(filepath)}


def main():
    manifest = []

    for city in sorted(os.listdir(BASE)):
        city_path = os.path.join(BASE, city)
        if not os.path.isdir(city_path) or city.startswith('.'):
            continue

        for district in sorted(os.listdir(city_path)):
            district_path = os.path.join(city_path, district)
            if not os.path.isdir(district_path) or district.startswith('.'):
                continue

            for team in sorted(os.listdir(district_path)):
                team_path = os.path.join(district_path, team)
                if not os.path.isdir(team_path) or not team.startswith("Team"):
                    continue

                for user_dir in sorted(os.listdir(team_path)):
                    user_path = os.path.join(team_path, user_dir)
                    if not os.path.isdir(user_path) or user_dir.startswith('.'):
                        continue

                    nickname, gender_code, display_name = parse_folder_name(user_dir)
                    gender = "female" if gender_code == "w" else "male"

                    # Файлы в папке
                    files = [f for f in os.listdir(user_path) if not f.startswith('.')]
                    has_avatar_jpg = "avatar.jpg" in files
                    has_avatar_webp = any(f.endswith('.webp') for f in files)
                    album_photos = sorted([f for f in files if f.startswith('photo_') and f.endswith('.jpg')])

                    # Определяем тип и is_closed
                    if has_avatar_jpg:
                        is_closed = False
                        avatar_kind = "custom"
                    elif has_avatar_webp:
                        is_closed = True
                        avatar_kind = "system"
                    else:
                        is_closed = True
                        avatar_kind = "system"

                    # Возраст
                    age = random.randint(20, 35)

                    # Предпочтения
                    rest_prefs = random.sample(REST_PREFERENCES, random.randint(1, 3))
                    rest_dis = random.sample(REST_DISLIKES, random.randint(0, 1))

                    # Фото
                    photos = []
                    if has_avatar_jpg:
                        avatar_path = os.path.join(user_path, "avatar.jpg")
                        info = get_photo_info(avatar_path)
                        photos.append({
                            "filename": "avatar.jpg",
                            "type": "avatar",
                            **info
                        })

                    for photo_file in album_photos:
                        photo_path = os.path.join(user_path, photo_file)
                        info = get_photo_info(photo_path)
                        photos.append({
                            "filename": photo_file,
                            "type": "album",
                            **info
                        })

                    entry = {
                        "city_slug": city,
                        "city_display": CITY_DISPLAY.get(city, city),
                        "district_slug": district,
                        "team_slug": team,
                        "folder_name": user_dir,
                        "nickname": nickname,
                        "gender": gender,
                        "display_name": display_name,
                        "age": age,
                        "is_closed": is_closed,
                        "avatar_kind": avatar_kind,
                        "has_avatar_jpg": has_avatar_jpg,
                        "rest_preferences": rest_prefs,
                        "rest_dislikes": rest_dis,
                        "photos": photos,
                    }
                    manifest.append(entry)

    # Статистика
    print(f"Всего пользователей: {len(manifest)}")
    print(f"  Москва: {sum(1 for m in manifest if m['city_slug'] == 'moskva')}")
    print(f"  Питер: {sum(1 for m in manifest if m['city_slug'] == 'sankt_peterburg')}")
    print(f"  Мужчин: {sum(1 for m in manifest if m['gender'] == 'male')}")
    print(f"  Женщин: {sum(1 for m in manifest if m['gender'] == 'female')}")
    print(f"  Закрытые (is_closed): {sum(1 for m in manifest if m['is_closed'])}")
    print(f"  С avatar.jpg: {sum(1 for m in manifest if m['has_avatar_jpg'])}")
    print(f"  С альбомными фото: {sum(1 for m in manifest if any(p['type'] == 'album' for p in m['photos']))}")
    total_album = sum(sum(1 for p in m['photos'] if p['type'] == 'album') for m in manifest)
    print(f"  Всего альбомных фото: {total_album}")

    # Команды
    teams = set()
    for m in manifest:
        teams.add((m['city_slug'], m['district_slug'], m['team_slug']))
    print(f"  Уникальных команд: {len(teams)}")

    with open(OUTPUT, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print(f"\nМанифест записан в {OUTPUT}")


if __name__ == '__main__':
    main()
