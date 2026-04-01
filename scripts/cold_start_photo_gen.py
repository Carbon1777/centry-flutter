#!/usr/bin/env python3
"""
Cold Start 2 — полный pipeline генерации фото для 250 пользователей.

Распределение:
- 10% (25) — пустые, без фото
- 10% (25) — системная аватарка, без альбома
- 8% (20) — сгенерированная аватарка, без альбома
- 72% (180) — сгенерированная аватарка + 2-6 фото в альбоме

Модели:
- Аватар: flux-2-pro
- Альбомные фото: flux-kontext-pro (с сохранением лица)
"""

import os, random, json, time, base64, shutil, urllib.request, sys

# === КОНФИГ ===
BASE = "/Users/jcat/Documents/Doc/Projects/cold_start2"
SYSTEM_AVATARS_DIR = "/Users/jcat/Documents/Doc/media/avatars/webp_512"
REPLICATE_TOKEN = "REPLICATE_TOKEN_REDACTED"
DRY_RUN = "--dry-run" in sys.argv  # для тестового прогона без API

# Системные аватарки по полу
FEMALE_AVATARS = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,  # все женские
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30,  # все женские
    37,  # розовые волосы — женская
    40,  # рыжая художница
    51, 52, 53, 54, 55, 56, 57, 58, 59, 60  # все женские
]

MALE_AVATARS = [
    11, 12, 13, 14, 15, 16, 17, 18,  # все мужские
    19,  # робот — мужской
    20,  # кепка
    31, 32, 33, 34, 35, 36,  # мужские
    38, 39,  # мальчики
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50  # все мужские
]

# Комбинаторный генератор уникальных локаций
# Место × действие × время/погода → тысячи комбинаций
PLACES = [
    # Еда и напитки
    "cafe", "coffee shop", "bakery", "restaurant", "sushi bar", "pizzeria",
    "food court", "wine bar", "rooftop bar", "pub", "beer garden",
    "ice cream parlor", "juice bar", "ramen shop",
    # Шопинг
    "shopping mall", "clothing store", "bookstore", "flower shop", "grocery store",
    "vintage shop", "electronics store", "souvenir shop",
    # Город
    "city street", "pedestrian crossing", "city square", "old town alley",
    "boulevard", "bridge over river", "embankment", "bus stop", "subway entrance",
    "tram stop", "cobblestone street", "downtown area",
    # Природа / парки
    "park bench", "botanical garden", "lake shore", "forest trail",
    "riverside walkway", "fountain area", "rose garden", "autumn park with fallen leaves",
    "snowy park in winter", "spring blooming garden",
    # Море / пляж
    "sandy beach with waves", "beach boardwalk", "seaside promenade",
    "beach bar with palm trees", "pier overlooking the sea",
    "rocky coast with sea view", "yacht marina", "tropical beach resort",
    "ocean sunset viewpoint",
    # Горы / природа
    "mountain hiking trail", "mountain viewpoint", "alpine meadow",
    "mountain lodge terrace", "ski resort", "cable car station",
    "waterfall viewpoint", "canyon overlook", "forest cabin porch",
    # Путешествия / южные страны
    "mediterranean old town street", "tropical garden", "palm tree alley",
    "ancient ruins", "moroccan style market", "turkish bazaar",
    "greek island white building", "italian piazza", "spanish courtyard",
    "balinese temple entrance", "thai street market",
    # Работа / учёба
    "office", "coworking space", "conference room", "office kitchen",
    "university campus", "library reading room", "lecture hall entrance",
    # Культура
    "art gallery", "museum hall", "theater lobby", "cinema lobby",
    "street art wall", "photography exhibition",
    # Спорт
    "gym", "yoga studio", "swimming pool area", "tennis court",
    "running track", "skateboard park", "climbing wall",
    # Развлечения
    "bowling alley", "karaoke room", "arcade", "escape room lobby",
    "amusement park ride", "ferris wheel", "go kart track",
    # Транспорт
    "train station", "airport terminal", "ferry dock", "vintage train car",
    # Разное
    "rooftop terrace", "balcony with city view", "hotel lobby", "hotel pool",
    "farmers market", "flea market", "christmas market", "street food festival",
    "concert venue", "jazz club", "outdoor music festival stage",
    "pottery workshop", "cooking class kitchen", "dance studio",
    "hair salon", "spa lobby",
    "ski resort lodge", "ice rink",
    # Сезоны
    "snowy city street in winter", "rainy city with umbrella",
    "cherry blossom spring park", "golden autumn forest path",
    "summer outdoor festival", "winter christmas decorated street",
]

ACTIVITIES = [
    "sitting at a table", "standing and chatting", "walking casually",
    "leaning against a wall", "looking at phone", "holding a drink",
    "taking a break", "waiting for someone", "browsing around",
    "sitting on a bench", "standing near entrance", "laughing at something",
    "eating food", "pointing at something", "posing casually for a friend",
    "reading something", "watching something in distance",
]

LIGHTING_CONDITIONS = [
    "bright sunny day", "overcast cloudy day", "golden hour warm light",
    "evening ambient lighting", "morning soft light", "harsh midday sun",
    "indoor fluorescent lighting", "warm cafe lamp light",
    "natural window light", "dim cozy lighting",
    "neon signs in background", "string lights decoration",
]

def generate_unique_location(used_set):
    """Генерирует уникальную комбинацию места+действие+свет."""
    for _ in range(200):
        place = random.choice(PLACES)
        activity = random.choice(ACTIVITIES)
        light = random.choice(LIGHTING_CONDITIONS)
        desc = f"{activity} at a {place}, {light}"
        if desc not in used_set:
            used_set.add(desc)
            return desc
    # fallback — добавляем рандомный суффикс
    desc = f"{random.choice(ACTIVITIES)} at a {random.choice(PLACES)}, {random.choice(LIGHTING_CONDITIONS)}, from a unique angle"
    used_set.add(desc)
    return desc

# Глобальный набор использованных локаций
USED_LOCATIONS = set()

# Волосы и одежда — раздельные списки для комбинаторного разнообразия
FEMALE_HAIR = [
    "brown hair shoulder length", "blonde hair in ponytail", "dark hair long straight",
    "auburn wavy hair", "light brown hair bob cut", "dark brown curly hair",
    "blonde hair loose", "brown hair with bangs", "red hair shoulder length",
    "dark hair in messy bun", "honey blonde hair medium", "black hair in low bun",
    "chestnut hair wavy", "strawberry blonde hair", "brown hair in french braid",
    "dark blonde hair with highlights", "brown hair half up half down",
    "black straight hair long", "light brown hair in clip", "ginger hair curly",
]

MALE_HAIR = [
    "short brown hair", "dark hair slightly longer", "blonde short hair",
    "brown hair medium", "dark short hair with stubble", "light brown hair",
    "black hair neat", "brown curly hair", "dirty blonde messy hair",
    "dark hair buzz cut", "brown hair side part", "dark wavy hair",
    "light hair crew cut", "brown hair textured top", "dark hair with fade",
    "sandy blonde hair", "black hair slicked back", "auburn short hair",
    "brown hair undercut", "dark hair with slight beard",
]

FEMALE_CLOTHES = [
    "wearing casual beige sweater", "wearing denim jacket over white top",
    "wearing black leather jacket", "wearing knit cardigan and jeans",
    "wearing white cotton blouse", "wearing grey hoodie",
    "wearing striped long sleeve shirt", "wearing burgundy turtleneck",
    "wearing green cargo jacket", "wearing oversized band t-shirt",
    "wearing blue denim shirt", "wearing pink puffer vest",
    "wearing cream colored coat", "wearing plaid flannel shirt",
    "wearing navy blazer casual style", "wearing mustard yellow sweater",
    "wearing olive green parka", "wearing simple black dress",
    "wearing light blue chambray shirt", "wearing coral colored top",
    "wearing brown suede jacket", "wearing lilac knit top",
    "wearing red checkered shirt", "wearing white cropped jacket",
    "wearing charcoal wool coat", "wearing teal blouse",
]

MALE_CLOTHES = [
    "wearing casual button-up shirt", "wearing grey hoodie and jeans",
    "wearing basic white t-shirt and jacket", "wearing navy polo shirt",
    "wearing dark green sweater", "wearing checked flannel shirt",
    "wearing black leather jacket", "wearing henley long sleeve shirt",
    "wearing denim jacket over tee", "wearing bomber jacket",
    "wearing light blue oxford shirt", "wearing maroon crew neck sweater",
    "wearing grey blazer casual", "wearing olive green field jacket",
    "wearing brown corduroy jacket", "wearing plain black t-shirt",
    "wearing cable knit sweater", "wearing quilted vest over shirt",
    "wearing rugby polo shirt", "wearing camel colored coat",
    "wearing burgundy zip hoodie", "wearing charcoal peacoat",
    "wearing striped long sleeve tee", "wearing tan chino jacket",
]

# Черты лица для уникальности
FACE_SHAPES = ["round face", "oval face", "square jawline", "heart-shaped face", "long face", "angular face"]
EYE_COLORS = ["brown eyes", "blue eyes", "green eyes", "hazel eyes", "dark brown eyes", "grey eyes"]
EYE_SHAPES = ["big round eyes", "narrow almond eyes", "deep-set eyes", "wide-set eyes", "hooded eyes"]
NOSE_TYPES = ["small nose", "straight nose", "wide nose", "slightly crooked nose", "button nose", "aquiline nose"]
SKIN_TONES = ["fair skin", "olive skin", "light tan skin", "pale skin", "warm beige skin", "medium skin tone"]
BODY_TYPES = ["slim build", "average build", "athletic build", "slightly chubby", "stocky build", "tall and lean"]
AGES_LOOK = ["looks younger than their age", "looks their age", "looks mature for their age"]
DISTINGUISHING = [
    "a few freckles on cheeks", "small scar on eyebrow", "dimples when smiling",
    "beauty mark near lips", "slightly crooked smile", "gap between front teeth",
    "laugh lines around eyes", "thick eyebrows", "thin lips", "full lips",
    "prominent cheekbones", "soft rounded chin", "cleft chin", "no distinguishing marks",
    "slight stubble", "clean shaven", "light acne scars",  # for males
]

USED_FACE_COMBOS = set()

def get_unique_face(gender):
    """Генерирует уникальную комбинацию черт лица."""
    for _ in range(300):
        face = random.choice(FACE_SHAPES)
        eyes_color = random.choice(EYE_COLORS)
        eyes_shape = random.choice(EYE_SHAPES)
        nose = random.choice(NOSE_TYPES)
        skin = random.choice(SKIN_TONES)
        body = random.choice(BODY_TYPES)
        mark = random.choice(DISTINGUISHING)
        combo = f"{face}, {eyes_color}, {eyes_shape}, {nose}, {skin}, {body}, {mark}"
        if combo not in USED_FACE_COMBOS:
            USED_FACE_COMBOS.add(combo)
            return combo
    # fallback
    return f"{random.choice(FACE_SHAPES)}, {random.choice(EYE_COLORS)}, {random.choice(SKIN_TONES)}, {random.choice(BODY_TYPES)}"

def get_appearance(gender):
    """Генерирует случайную комбинацию волосы + одежда."""
    if gender == 'w':
        return f"{random.choice(FEMALE_HAIR)}, {random.choice(FEMALE_CLOTHES)}"
    else:
        return f"{random.choice(MALE_HAIR)}, {random.choice(MALE_CLOTHES)}"


def get_all_users():
    """Собирает всех пользователей из директории."""
    users = []
    for city in sorted(os.listdir(BASE)):
        city_path = os.path.join(BASE, city)
        if not os.path.isdir(city_path) or city.startswith('.'):
            continue
        for district in sorted(os.listdir(city_path)):
            district_path = os.path.join(city_path, district)
            if not os.path.isdir(district_path):
                continue
            for team in sorted(os.listdir(district_path)):
                team_path = os.path.join(district_path, team)
                if not os.path.isdir(team_path) or not team.startswith("Team"):
                    continue
                for user_dir in sorted(os.listdir(team_path)):
                    user_path = os.path.join(team_path, user_dir)
                    if not os.path.isdir(user_path) or user_dir.startswith('.'):
                        continue
                    # Определяем пол из имени папки
                    gender = 'w' if '_w ' in user_dir or '_w(' in user_dir else 'm'
                    users.append({
                        'path': user_path,
                        'dir_name': user_dir,
                        'gender': gender,
                        'city': city,
                        'district': district,
                        'team': team,
                    })
    return users


def assign_roles(users):
    """Распределяет роли случайным образом."""
    random.shuffle(users)
    n = len(users)

    # 10% пустые
    n_empty = round(n * 0.10)
    # 10% системные аватарки
    n_system = round(n * 0.10)
    # 10% от оставшихся — только аватарка
    n_remaining = n - n_empty - n_system
    n_avatar_only = round(n_remaining * 0.10)
    # остальные — аватарка + альбом
    n_full = n_remaining - n_avatar_only

    idx = 0
    for i in range(n_empty):
        users[idx]['role'] = 'empty'
        idx += 1
    for i in range(n_system):
        users[idx]['role'] = 'system'
        idx += 1
    for i in range(n_avatar_only):
        users[idx]['role'] = 'avatar_only'
        users[idx]['age'] = random.randint(25, 35)
        idx += 1
    for i in range(n_full):
        users[idx]['role'] = 'full'
        users[idx]['age'] = random.randint(25, 35)
        users[idx]['album_count'] = random.randint(2, 6)
        idx += 1

    return users


def copy_system_avatar(user):
    """Копирует случайную системную аватарку соответствующего пола."""
    if user['gender'] == 'w':
        avatar_num = random.choice(FEMALE_AVATARS)
    else:
        avatar_num = random.choice(MALE_AVATARS)

    src = os.path.join(SYSTEM_AVATARS_DIR, f"avatar_{avatar_num:02d}.webp")
    dst = os.path.join(user['path'], "avatar.webp")
    shutil.copy2(src, dst)
    return avatar_num


def replicate_predict(model, input_data, max_wait=120):
    """Запускает предикт и ждёт результат."""
    if DRY_RUN:
        print(f"  [DRY RUN] Would call {model}")
        return "https://example.com/fake.jpg"

    url = f"https://api.replicate.com/v1/models/{model}/predictions"
    data = json.dumps({"input": input_data}).encode()

    for attempt in range(3):
        try:
            req = urllib.request.Request(url, data=data, headers={
                "Authorization": f"Bearer {REPLICATE_TOKEN}",
                "Content-Type": "application/json"
            })
            resp = urllib.request.urlopen(req)
            result = json.loads(resp.read())
            pred_id = result['id']
            break
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = 15
                print(f"  Rate limited, waiting {wait}s...")
                time.sleep(wait)
                continue
            raise
    else:
        raise RuntimeError("Failed after 3 attempts")

    # Поллинг
    get_url = f"https://api.replicate.com/v1/predictions/{pred_id}"
    for _ in range(max_wait // 3):
        time.sleep(3)
        req = urllib.request.Request(get_url, headers={
            "Authorization": f"Bearer {REPLICATE_TOKEN}"
        })
        resp = urllib.request.urlopen(req)
        result = json.loads(resp.read().decode('utf-8', errors='replace'))

        if result['status'] == 'succeeded':
            out = result.get('output')
            if isinstance(out, list):
                return out[0]
            return out
        elif result['status'] == 'failed':
            print(f"  FAILED: {result.get('error', 'unknown')}")
            return None

    print(f"  TIMEOUT for {pred_id}")
    return None


def generate_avatar(user):
    """Генерирует аватар через flux-2-pro."""
    gender_word = "woman" if user['gender'] == 'w' else "man"
    age = user.get('age', random.randint(25, 35))

    appearance = get_appearance(user['gender'])
    face_features = get_unique_face(user['gender'])

    location = generate_unique_location(USED_LOCATIONS)

    prompt = (
        f"casual photo taken by a friend of a regular young {gender_word} {age}yo "
        f"{location}, upper body shot, {appearance}, "
        f"{face_features}, "
        f"realistic human skin with visible pores and natural texture, "
        f"not a selfie, phone camera from normal distance, regular looking person not a model, "
        f"candid relaxed moment, matte skin not glossy, no retouching no skin smoothing"
    )

    result_url = replicate_predict("black-forest-labs/flux-2-pro", {
        "prompt": prompt,
        "aspect_ratio": "2:3",
        "output_format": "jpg",
        "safety_tolerance": 5
    })

    if result_url and not DRY_RUN:
        dst = os.path.join(user['path'], "avatar.jpg")
        urllib.request.urlretrieve(result_url, dst)
        return dst
    return None


POSES = [
    "standing and looking at camera", "walking towards camera",
    "sitting on a chair leaning back", "leaning against a railing",
    "holding a coffee cup in hand", "looking to the side laughing",
    "arms crossed standing confidently", "sitting cross-legged on grass",
    "waving at the camera", "pointing at something off-camera",
    "hands in pockets standing casually", "taking a selfie with one hand up",
    "crouching down near ground level", "stretching arms up",
    "riding a bicycle", "holding a shopping bag",
    "sitting on stairs", "dancing or moving dynamically",
    "hugging a friend from behind", "jumping in the air",
    "eating food with hands", "reading a book or magazine",
    "sitting on a ledge dangling feet", "running playfully",
]

def generate_album_photo(user, photo_num, avatar_path, location_desc):
    """Генерирует фото для альбома через flux-kontext-pro."""
    gender_word = "woman" if user['gender'] == 'w' else "man"
    location = location_desc
    pose = random.choice(POSES)
    clothes = get_appearance(user['gender']).split(', wearing ')[-1] if ', wearing ' in get_appearance(user['gender']) else random.choice(FEMALE_CLOTHES if user['gender'] == 'w' else MALE_CLOTHES)

    with open(avatar_path, 'rb') as f:
        b64 = base64.b64encode(f.read()).decode()

    prompt = (
        f"Same face as the person in the image but in a completely different scene. "
        f"The person is now {location}, {pose}, {clothes}. "
        f"Different outfit and pose from the reference image. "
        f"Photo taken by a friend with phone camera, candid moment, "
        f"regular person not a model, realistic skin"
    )

    result_url = replicate_predict("black-forest-labs/flux-kontext-pro", {
        "prompt": prompt,
        "input_image": f"data:image/jpeg;base64,{b64}",
        "aspect_ratio": "2:3",
        "output_format": "jpg",
        "safety_tolerance": 5
    })

    if result_url and not DRY_RUN:
        dst = os.path.join(user['path'], f"photo_{photo_num}.jpg")
        urllib.request.urlretrieve(result_url, dst)
        return dst
    return None


def clean_user_folder(user_path):
    """Очищает папку пользователя от старых файлов."""
    for f in os.listdir(user_path):
        fp = os.path.join(user_path, f)
        if os.path.isfile(fp) and not f.startswith('.'):
            os.remove(fp)


def main():
    print("=== Cold Start 2 Photo Generation ===")
    if DRY_RUN:
        print(">>> DRY RUN MODE — no API calls <<<\n")

    # 1. Собираем пользователей
    users = get_all_users()
    print(f"Найдено пользователей: {len(users)}")
    print(f"  Женщин: {sum(1 for u in users if u['gender'] == 'w')}")
    print(f"  Мужчин: {sum(1 for u in users if u['gender'] == 'm')}")

    # 2. Распределяем роли
    users = assign_roles(users)

    roles = {}
    for u in users:
        r = u['role']
        roles[r] = roles.get(r, 0) + 1
    print(f"\nРаспределение:")
    print(f"  Пустые: {roles.get('empty', 0)}")
    print(f"  Системные аватарки: {roles.get('system', 0)}")
    print(f"  Только аватарка: {roles.get('avatar_only', 0)}")
    print(f"  Полные (аватар+альбом): {roles.get('full', 0)}")

    total_album = sum(u.get('album_count', 0) for u in users if u.get('role') == 'full')
    total_gen = roles.get('avatar_only', 0) + roles.get('full', 0)  # avatars to generate
    print(f"\nГенерируем:")
    print(f"  Аватаров: {total_gen}")
    print(f"  Альбомных фото: {total_album}")
    print(f"  ИТОГО: {total_gen + total_album}")

    if DRY_RUN:
        # Выводим план
        for u in sorted(users, key=lambda x: x['path']):
            info = f"  [{u['role']}] {u['gender'].upper()} "
            if u['role'] == 'full':
                info += f"age={u['age']} album={u['album_count']} "
            elif u['role'] == 'avatar_only':
                info += f"age={u['age']} "
            info += os.path.basename(u['path'])
            print(info)
        return

    # 3. Обрабатываем
    # Сначала сортируем: system и empty — быстро, потом avatar_only, потом full
    processed = 0
    failed = 0

    # 3a. Пустые — просто чистим
    for u in users:
        if u['role'] == 'empty':
            clean_user_folder(u['path'])
            processed += 1
    print(f"\n[{processed}/{len(users)}] Пустые папки очищены")

    # 3b. Системные аватарки
    for u in users:
        if u['role'] == 'system':
            clean_user_folder(u['path'])
            num = copy_system_avatar(u)
            processed += 1
            print(f"  [{processed}] System avatar_{num:02d} -> {os.path.basename(u['path'])}")
    print(f"[{processed}/{len(users)}] Системные аватарки скопированы")

    # 3c. Аватарки без альбома
    for u in users:
        if u['role'] == 'avatar_only':
            existing = os.path.join(u['path'], 'avatar.jpg')
            if os.path.exists(existing):
                processed += 1
                print(f"  [{processed}] SKIP (already has avatar): {os.path.basename(u['path'])}")
                continue
            clean_user_folder(u['path'])
            print(f"\n  [{processed+1}] Generating avatar for {os.path.basename(u['path'])} ({u['gender'].upper()}, {u['age']}yo)...")
            result = generate_avatar(u)
            processed += 1
            if result:
                print(f"    OK: {result}")
            else:
                print(f"    FAILED")
                failed += 1
            time.sleep(2)  # rate limit buffer
    print(f"\n[{processed}/{len(users)}] Аватарки без альбома готовы")

    # 3d. Полные — аватарка + альбом
    for u in users:
        if u['role'] == 'full':
            name = os.path.basename(u['path'])
            existing_avatar = os.path.join(u['path'], 'avatar.jpg')
            existing_photos = [f for f in os.listdir(u['path']) if f.startswith('photo_') and f.endswith('.jpg')]
            if os.path.exists(existing_avatar) and len(existing_photos) >= u.get('album_count', 2):
                processed += 1
                print(f"  [{processed}] SKIP (already complete): {name}")
                continue
            # Проверяем что уже есть
            has_avatar = os.path.exists(existing_avatar)
            existing_count = len(existing_photos)
            needed = u['album_count'] - existing_count

            print(f"\n  [{processed+1}] {name} ({u['gender'].upper()}, {u['age']}yo, need {needed} more photos, has_avatar={has_avatar})...")

            # Генерим аватарку если нет
            if has_avatar:
                avatar_path = existing_avatar
                print(f"    Avatar EXISTS, reusing")
            else:
                avatar_path = generate_avatar(u)
                if not avatar_path:
                    print(f"    Avatar FAILED, skipping album")
                    failed += 1
                    processed += 1
                    continue
                print(f"    Avatar OK")
                time.sleep(2)

            # Генерим только недостающие альбомные фото
            start_idx = existing_count + 1
            for i in range(start_idx, u['album_count'] + 1):
                loc = generate_unique_location(USED_LOCATIONS)
                print(f"    Photo {i}/{u['album_count']} ({loc[:40]}...)...", end=" ")
                photo = generate_album_photo(u, i, avatar_path, loc)
                if photo:
                    print("OK")
                else:
                    print("FAILED")
                    failed += 1
                time.sleep(2)

            processed += 1

    print(f"\n=== DONE ===")
    print(f"Processed: {processed}/{len(users)}")
    print(f"Failed: {failed}")


if __name__ == '__main__':
    main()
