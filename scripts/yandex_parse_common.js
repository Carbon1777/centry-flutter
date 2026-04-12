#!/usr/bin/env node
/**
 * Общий модуль для парсинга Яндекс.Карт v2.
 *
 * Экспортирует:
 *   - AREAS — районы по городам (из core_areas)
 *   - PLACE_TYPES — типы мест для поиска
 *   - STOP_WORDS — стоп-слова для фильтрации
 *   - createParser(scriptName, areas) — фабрика парсера
 */
import { chromium } from 'playwright';
import sharp from 'sharp';
import fs from 'fs';
import path from 'path';
import https from 'https';
import http from 'http';
import readline from 'readline';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ── Типы мест ──────────────────────────────────────────
export const PLACE_TYPES = [
  'Бар',
  'Ресторан',
  'Ночной клуб',
  'Сауна',
  'Кальянная',
  'Караоке',
];

// ── Стоп-слова для фильтрации ──────────────────────────
const STOP_WORDS_NAME = [
  'магазин', 'shop', 'store', 'маркет', 'market',
  'школа', 'студия', 'курсы', 'обучение', 'академия',
  'фитнес', 'fitness', 'тренажёрный', 'тренажерный', 'спортзал', 'gym',
  'доставка', 'delivery', 'еда на вынос',
  'аптека', 'клиника', 'стоматолог', 'медицинский', 'мед. центр',
  'салон красоты', 'парикмахерская', 'барбершоп', 'косметолог', 'маникюр',
  'автосервис', 'автомойка', 'шиномонтаж', 'автозапчасти',
  'агентство', 'консалтинг', 'юридическ', 'бухгалтер',
  'шоурум', 'showroom', 'склад', 'оптовый', 'оптовая',
  'детский', 'детская', 'для детей', 'ребёнок',
  'шаурма', 'шаверма', 'хинкальная', 'столовая', 'буфет',
  'пивной магазин', 'винотека', 'алкомаркет',
  'хостел', 'гостиница', 'отель', 'hotel',
  'прачечная', 'химчистка', 'ремонт обуви', 'ателье',
  'ритуальные', 'похоронные',
  'церковь', 'храм', 'мечеть', 'синагога',
  'ломбард', 'букмекер', 'ставки',
  'киберспорт', 'компьютерный клуб', 'игровой зал', 'игровой клуб',
  'компьютерный зал', 'игровая', 'gaming', 'game center',
  'массажный', 'мир массажа',
  'прачечная', 'стирка', 'химчистка',
  'спа-салон', 'spa-салон', 'бьюти',
  'аренда караоке', 'аренда зала',
  'квест', 'антикафе', 'коворкинг', 'coworking',
  'лазертаг', 'пейнтбол', 'батут', 'картинг',
  'escape', 'виртуальн', 'vr-',
  'кондитерская', 'пекарня',
  'цветочн', 'флорист',
  'нотариус', 'типография',
  'страхов', 'страховая',
];

const STOP_WORDS_CATEGORY = [
  'магазин', 'shop', 'store', 'маркет',
  'школа', 'студия', 'курсы', 'обучение',
  'фитнес', 'fitness', 'тренажёрный', 'gym', 'спорт',
  'доставка', 'delivery',
  'аптека', 'клиника', 'стоматолог', 'медицин',
  'салон красоты', 'парикмахерская', 'барбершоп',
  'автосервис', 'автомойка', 'шиномонтаж',
  'агентство', 'консалтинг',
  'детский', 'для детей',
  'хостел', 'гостиница', 'отель',
  'супермаркет', 'гипермаркет', 'продуктовый',
  'киберспорт', 'компьютерный', 'игровой', 'gaming',
  'массажный', 'спа-салон', 'бьюти', 'beauty',
  'прачечная', 'химчистка', 'стирка',
  'квест', 'антикафе', 'коворкинг',
  'лазертаг', 'пейнтбол', 'батут', 'картинг',
  'кондитерская', 'пекарня', 'выпечка',
  'цветочный', 'флористика',
  'нотариальный', 'типография', 'страховой',
];

const STOP_WORDS_SITE = [
  'shop', 'store', 'fitness', 'school', 'delivery',
  'magazine', 'avto', 'auto', 'clinic', 'salon',
  'dance', 'apteka', 'stomatolog', 'detsk', 'kids',
  'hostel', 'hotel', 'booking', 'laundry',
];

// ── Районы из core_areas (snapshot) ────────────────────
export const AREAS = {
  'Москва': [
    { id: '218b635a-10f0-4cd6-bb99-a3ba123a6c03', name: 'Академический район' },
    { id: '7763085f-a6ae-49cb-a66d-9aea2b2dbeb1', name: 'Алексеевский район' },
    { id: '609f1d2b-cb8c-4e7a-9979-da1695ebbcf8', name: 'Алтуфьевский район' },
    { id: '9a6336f7-5404-4b0a-801d-88f7f23e9930', name: 'Бабушкинский район' },
    { id: 'e117ded8-abc7-4907-988f-3c50acb2356a', name: 'Басманный район' },
    { id: '65023122-291d-409b-ae67-18f03717cc99', name: 'Бескудниковский район' },
    { id: 'fc485e6b-fd97-4e7b-9ba0-91069a6a5838', name: 'Бутырский район' },
    { id: '31bb4b09-6978-4ac4-a09e-538c000862dd', name: 'Войковский район' },
    { id: '74130ad0-aeea-4bd1-a0e5-066c54edb036', name: 'Гагаринский район' },
    { id: '01d66bed-7e7f-43cc-9aec-72e115ead09b', name: 'Головинский район' },
    { id: '6f4dcaa7-8097-4ebb-92e5-0bcb4335d3ce', name: 'Даниловский район' },
    { id: 'cf224ac5-c121-4367-9c5b-3780bedb433d', name: 'Дмитровский район' },
    { id: 'cc33b9c4-c6ef-4f2b-9f74-7d5da5f28f68', name: 'Донской район' },
    { id: 'e6912241-0968-419a-a40d-8574ad9eff0b', name: 'Краснопахорский район' },
    { id: 'b669a58b-73d2-4b07-afbc-7d5c571a0b53', name: 'Красносельский район' },
    { id: '57de7aed-f902-47a4-a2b3-3d824e8d6cfc', name: 'Ломоносовский район' },
    { id: 'c5a8919c-940d-41b2-b784-0ac686ada561', name: 'Лосиноостровский район' },
    { id: 'eda88ff6-f97e-4ae9-b3fe-8fd322ef3312', name: 'Мещанский район' },
    { id: '8433907e-3abe-484a-ae83-a56ceb09d037', name: 'Можайский район' },
    { id: 'dd504738-1cb1-4a2f-bac2-4341669fd340', name: 'Молжаниновский район' },
    { id: '03db6d49-aca4-4008-b4a9-6b9569d3294f', name: 'Нагорный район' },
    { id: '24932ce0-ed5f-4683-a382-400e49e64211', name: 'Нижегородский район' },
    { id: '7fc48466-7c86-4aa9-af27-8012fd2ce57a', name: 'Ново-Переделкино' },
    { id: '1ae511a7-2aed-462e-8ece-b576c53bf428', name: 'Обручевский район' },
    { id: '0b65e5f1-b616-4c8b-8665-3214ea32c089', name: 'Орехово-Борисово Южное' },
    { id: '97782a85-dd50-42e0-a957-6deb7cb91b61', name: 'Останкинский район' },
    { id: 'c0dca447-1c2f-49a9-800d-a12d41c7e3de', name: 'Пресненский район' },
    { id: 'e06ca84f-746b-4878-9f09-12f2d6f43df0', name: 'район Арбат' },
    { id: '5f217e24-c159-4c56-977d-06d22c6daf93', name: 'район Аэропорт' },
    { id: '9dc087f7-d5d6-4dde-a9de-7bb75e2ca81d', name: 'район Беговой' },
    { id: '00608d5e-751b-42d6-a7de-caafb75a69ed', name: 'район Бекасово' },
    { id: 'fd17d503-25a8-4b6f-b0a3-9222e83f03df', name: 'район Бибирево' },
    { id: 'f154fd5f-40af-4500-9d73-a6afe1b83256', name: 'район Бирюлёво Восточное' },
    { id: '1f3d0f58-cc12-4ddb-826b-ff1da0896923', name: 'район Бирюлёво Западное' },
    { id: '9c464d80-2fca-41b7-948a-dec9f82ab0a2', name: 'район Богородское' },
    { id: '7e0bc238-1686-49f9-81b3-cd9acb7d9234', name: 'район Братеево' },
    { id: '2a6dd76a-100c-4068-be5a-2f4a8f6ce1be', name: 'район Вешняки' },
    { id: '511e5bd9-2ec8-4b35-8470-1608024b9320', name: 'район Внуково' },
    { id: 'f4983a62-e6ab-4b6b-aa4f-a331404351a0', name: 'район Вороново' },
    { id: 'e75e9d43-23c7-4ce6-9aed-867aab33b876', name: 'район Восточное Дегунино' },
    { id: 'e71a09fd-0b0b-4110-9224-c9ec58604e12', name: 'район Восточное Измайлово' },
    { id: 'fdc67728-f962-4080-bb28-d6186476a840', name: 'район Восточный' },
    { id: '0932ec10-4ba3-4ad6-96e7-310a86ba48d0', name: 'район Выхино-Жулебино' },
    { id: 'dad940d1-2fcd-453c-be5e-34071a4eac6e', name: 'район Гольяново' },
    { id: '8ea8d0d7-2080-4cbe-b630-94f04976410f', name: 'район Дорогомилово' },
    { id: '67f27fab-1c28-4d99-b739-b2c7a1f5d5ee', name: 'район Замоскворечье' },
    { id: 'e1aa4e13-2675-4d7e-86f0-ef679d5d8ad6', name: 'район Западное Дегунино' },
    { id: '45df36fe-1a7f-4f19-900d-ace1f5a439af', name: 'район Зюзино' },
    { id: 'cfc45088-1f44-44d2-aa20-0395373eb6df', name: 'район Зябликово' },
    { id: 'e4ef550c-5d64-478d-9bdf-e10e3c226def', name: 'район Ивановское' },
    { id: '6872fa70-f088-4d58-9d32-5863b1fcfe3b', name: 'район Измайлово' },
    { id: '65cb7023-4607-4c1a-bf23-96da2af7611e', name: 'район Капотня' },
    { id: 'd3c2d5f9-374b-4380-838a-35032b52a338', name: 'район Коммунарка' },
    { id: '103ef2ea-220b-4c3b-8640-8586a6d2a22b', name: 'район Коньково' },
    { id: 'a89b7b93-0553-4247-8d61-f12f45b1671f', name: 'район Коптево' },
    { id: 'ef6369bd-7d25-4e5c-a6be-c38d1ce3292c', name: 'район Косино-Ухтомский' },
    { id: '454b5e1c-15a8-41f6-bbdd-ed2c323432f4', name: 'район Котловка' },
    { id: '12658332-38ce-480a-88ec-d954abffc8d8', name: 'район Крылатское' },
    { id: '2501bee4-5200-4bdd-89bf-9dc4d448a0d0', name: 'район Крюково' },
    { id: 'acf2db8c-262e-4ec6-8cc3-1e100ada5b0b', name: 'район Кузьминки' },
    { id: '2764d922-bb6c-4dd8-8729-5087e9a219b2', name: 'район Кунцево' },
    { id: '836437d1-8e44-4676-9eca-52a94a30bc26', name: 'район Куркино' },
    { id: '3490cfce-24d1-4cd5-8732-a5c09ba27bbc', name: 'район Левобережный' },
    { id: '712bf5c3-14d7-4923-bf44-881ae5251fdd', name: 'район Лефортово' },
    { id: 'f9498651-00bd-49f3-899c-d7f6d420f4c2', name: 'район Лианозово' },
    { id: 'dbc4a2cb-770b-4e2d-96c1-1433bed5a6de', name: 'район Люблино' },
    { id: '93049173-0368-4be2-a9d3-3ab9baa30e74', name: 'район Марфино' },
    { id: '4d9d8872-ef47-492b-a7b9-aa2040eca7e4', name: 'район Марьина Роща' },
    { id: 'db9224ae-4479-42cb-826b-e5addb832e0d', name: 'район Марьино' },
    { id: 'b2e5e43c-8270-4e2e-bc04-58e74ed9555e', name: 'район Матушкино' },
    { id: '8941a326-242b-4e49-801f-81df306a7461', name: 'район Метрогородок' },
    { id: '1ed5a825-8842-4332-9e01-ea1d61919751', name: 'район Митино' },
    { id: 'd95cf9ac-abb5-4920-a19b-9f345a34c670', name: 'район Москворечье-Сабурово' },
    { id: 'c191b9e5-2130-459b-9d60-3d7b7d0823c0', name: 'район Нагатино-Садовники' },
    { id: 'f4a13711-97e1-4dc8-9f9d-b955645d3416', name: 'район Нагатинский Затон' },
    { id: '6418a928-d2cc-4d17-87c1-7bbeef43a1ca', name: 'район Некрасовка' },
    { id: '8c84eba9-45a6-488c-9f4e-8123c95372cc', name: 'район Новогиреево' },
    { id: '6b8543fb-4d97-49ea-860e-8193985550e6', name: 'район Новокосино' },
    { id: 'df8368f1-bf65-4437-83b0-3b6b1f502b28', name: 'район Орехово-Борисово Северное' },
    { id: '278e7f21-74aa-4f6e-ac25-af8a97496fe7', name: 'район Отрадное' },
    { id: '8206bb91-08d6-495b-a502-03cba3e8c646', name: 'район Очаково-Матвеевское' },
    { id: '716df334-78cf-4925-b877-6d184eb5b0d7', name: 'район Перово' },
    { id: '732176a5-9b5f-4a27-8c2b-3ace96dab023', name: 'район Печатники' },
    { id: '4b0f1697-5214-494e-8480-d3937f51f6fd', name: 'район Покровское-Стрешнево' },
    { id: '000ecdd4-6f96-4761-bfa3-5f72912bece6', name: 'район Преображенское' },
    { id: '3b3781f6-40de-4d16-a81b-15a1abbd471f', name: 'район Проспект Вернадского' },
    { id: '66c15222-cc35-4a68-913a-66aca3318542', name: 'район Раменки' },
    { id: 'bdee2cf5-c774-472f-b6c6-4b513a17d6d8', name: 'район Ростокино' },
    { id: '2397a011-79d2-4e63-b7bc-66b5aa6b53b9', name: 'район Савёлки' },
    { id: '10078bf1-0ddf-4b23-9a3b-9cc03eb72e07', name: 'район Свиблово' },
    { id: '05944351-d9d6-41df-9419-f4a1a6efcf98', name: 'район Северное Бутово' },
    { id: '92d6efbd-1173-4691-97ca-560bb96f0a83', name: 'район Северное Измайлово' },
    { id: '82f144ac-563e-4fcd-94ae-6eb6c82d294b', name: 'район Северное Медведково' },
    { id: '78e8b52f-5f11-4dc7-ae04-b697c291c398', name: 'район Северное Тушино' },
    { id: '57af475f-6d47-4afe-a0f2-88a88427e877', name: 'район Северный' },
    { id: 'bf3b61cf-915e-4da7-91dd-cfbca8020b59', name: 'район Силино' },
    { id: 'c34dfa74-1e28-4c22-9881-7fa7265e1d3f', name: 'район Сокол' },
    { id: 'b07ad956-aba6-4990-93d1-d7f7341d984f', name: 'район Соколиная Гора' },
    { id: '6990a204-900e-40bb-b049-977582547e67', name: 'район Сокольники' },
    { id: '470ba33c-aed5-4d79-8611-b7ef32ca6153', name: 'район Солнцево' },
    { id: 'f196e2cc-633b-496a-8bc8-392df58bd641', name: 'район Старое Крюково' },
    { id: 'a7888697-4097-4498-ba3b-3d43c32e4fe3', name: 'район Строгино' },
    { id: 'f959f915-e37a-451a-819f-eaf79a9fe811', name: 'район Текстильщики' },
    { id: '9ca28530-9478-4592-86f0-2232d0352118', name: 'район Тёплый Стан' },
    { id: '44796763-d7cf-4a9d-9984-64561a04bcd6', name: 'район Троицк' },
    { id: 'db98f54a-5cd9-4fca-baca-5c96e23f8fff', name: 'район Филёвский Парк' },
    { id: '07788fde-c511-4198-8889-ecd11d110ae4', name: 'район Фили-Давыдково' },
    { id: '73572eeb-022e-4e11-8216-14fb60bdc222', name: 'район Хамовники' },
    { id: '38df31c0-269a-4e9a-a7bc-8ac3fa57db47', name: 'район Ховрино' },
    { id: 'ce97cdec-5daa-44c9-8de4-55f93bc2f3e3', name: 'район Хорошёво-Мнёвники' },
    { id: '4ed67162-5970-4dd9-b229-f489aa861758', name: 'район Царицыно' },
    { id: '2e881d11-b82e-43de-980d-cb313f864c09', name: 'район Черёмушки' },
    { id: '364c7a12-a1fc-4d28-83e1-dcb6430bf206', name: 'район Чертаново Северное' },
    { id: 'ca4889c2-47e8-4307-9c7b-badbed0c96a0', name: 'район Чертаново Центральное' },
    { id: 'd386ea6d-c4b8-4778-a8d3-127aebdff952', name: 'район Чертаново Южное' },
    { id: '6b100b11-72b0-46da-aa7e-ba595384f1be', name: 'район Щербинка' },
    { id: 'b055ebbf-f771-415e-8c5f-9ccf2f769373', name: 'район Щукино' },
    { id: 'c13a250c-dbac-4ff2-8d06-6bc9b4f3310f', name: 'район Южное Бутово' },
    { id: 'f51a7c75-a15c-4f79-abf7-548dc6a0236c', name: 'район Южное Медведково' },
    { id: '70f3debf-7270-4937-a3fc-3f3eeae0cbe2', name: 'район Южное Тушино' },
    { id: '1eee5881-5cad-4c87-a07d-cdeb6e023535', name: 'район Якиманка' },
    { id: '9c80fe61-b6de-49fd-bf73-d3ec822f6209', name: 'район Ясенево' },
    { id: '9d4ae8b5-ac8c-4632-b75f-01a8322c411b', name: 'Рязанский район' },
    { id: 'cb60d3ad-6bfc-4e95-818b-00bf9b76763a', name: 'Савёловский район' },
    { id: 'cd16eac0-d1ac-47d8-8b43-ce34319f1218', name: 'Таганский район' },
    { id: 'a9261874-fbf9-4759-a56d-f6281ae30a77', name: 'Тверской район' },
    { id: '6567f7ac-ed11-4628-b826-84a0057c1425', name: 'Тимирязевский район' },
    { id: 'be8c3fa9-7547-4c21-9a9d-49a37af43dda', name: 'Тропарёво-Никулино' },
    { id: '8ceb2f27-7421-41d6-a3c7-da8b744ebb58', name: 'Филимонковский район' },
    { id: '680b5102-9961-4008-ac7c-dd266a362938', name: 'Хорошёвский район' },
    { id: '68b16b70-7911-4baa-abea-3605856ad57a', name: 'Южнопортовый район' },
    { id: 'e0471946-cb47-4350-bfc3-09ccef881b3f', name: 'Ярославский район' },
  ],
  'Санкт-Петербург': [
    { id: '8a3df2bc-20ef-447b-b90a-68fcea5fa157', name: 'Адмиралтейский район' },
    { id: '6b360930-b46f-430a-b787-f71774ed2e4f', name: 'Василеостровский район' },
    { id: '7894db44-63f4-49cd-82b6-04dd8a248b62', name: 'Выборгский район' },
    { id: '0126e91b-4540-4993-bfae-356a1637c06b', name: 'Калининский район' },
    { id: 'e1b41b83-7126-43c1-b563-67e1afbe6569', name: 'Кировский район' },
    { id: '195f6389-fe0c-4016-846d-9afdea48190c', name: 'Колпинский район' },
    { id: '031bc653-e700-4a92-a84d-614bda343c1d', name: 'Красногвардейский район' },
    { id: '42a8df12-0d62-4333-8846-b15718243be4', name: 'Красносельский район' },
    { id: '77930868-d60b-4784-9df8-f1332e8f5099', name: 'Кронштадтский район' },
    { id: 'c8c9024a-528a-4719-a3e3-86cf42e33cb2', name: 'Курортный район' },
    { id: '14de81be-c8c0-4022-b819-2fdca65a7fee', name: 'Московский район' },
    { id: 'aa256212-1ba4-496d-8717-ba3d43d48acb', name: 'Невский район' },
    { id: '1d70d824-cc39-4080-8baa-0353fd895254', name: 'Петроградский район' },
    { id: '2e97f339-10d6-4cf7-870f-79e19adceb44', name: 'Петродворцовый район' },
    { id: 'e602ea63-9109-4f54-aa32-4bbfc4e1eb30', name: 'Приморский район' },
    { id: 'a79d23bc-ec76-4015-95b2-a0c290a4449c', name: 'Пушкинский район' },
    { id: '24b986b2-4aab-45b5-ad3b-df8b9b53b7e7', name: 'Фрунзенский район' },
    { id: '9b633019-04a6-41de-af48-09c243b9453d', name: 'Центральный район' },
  ],
  'Казань': [
    { id: '3b2e8152-2e4d-43b1-bf49-3ac76e7a301a', name: 'Авиастроительный' },
    { id: '3f88a0c2-296b-4318-ae31-d6683aaa058e', name: 'Вахитовский' },
    { id: '659effca-080d-46c1-9fca-eaeeb0eb986f', name: 'Кировский' },
    { id: 'b68c59c5-ed8b-481d-9d24-27065cb9b4e1', name: 'Московский' },
    { id: '987f7471-d876-425b-b2e7-8a01558e0c45', name: 'Ново-Савиновский' },
    { id: '7e899644-0016-4fb0-8b99-691ca4226ffb', name: 'Приволжский' },
    { id: '97a6ab8e-9035-4a38-8a09-47c3bfac0ab5', name: 'Советский' },
  ],
  'Краснодар': [
    { id: 'd722370f-5634-4021-b562-07e99c8628b2', name: 'Западный' },
    { id: '0b1fa56a-dcaf-4653-84b2-f7a4a9f27263', name: 'Карасунский' },
    { id: '2305fc85-11fb-4209-b6f6-b5f543d9630e', name: 'Прикубанский' },
    { id: '77eb3013-ed4b-4144-bc00-703ea4668db3', name: 'Центральный' },
  ],
  'Нижний Новгород': [
    { id: 'afa87a0b-c328-4479-8acc-7faa6086b2c1', name: 'Автозаводский' },
    { id: 'e7ef9f43-1045-4c27-9ef5-310467c21763', name: 'Канавинский' },
    { id: '0d6c1735-c7bd-485e-85e1-f02ebf9f804d', name: 'Ленинский' },
    { id: 'ec304ba6-de68-4674-b7db-719659ec7ecd', name: 'Московский' },
    { id: 'a1ed214b-7dac-45f7-b07b-e823f75b9930', name: 'Нижегородский' },
    { id: 'd444ff41-26c2-4c96-b30f-000fd3d99595', name: 'Приокский' },
    { id: 'c1431821-79e5-421e-b9ee-c0abac593c08', name: 'Советский' },
    { id: '829eed75-e50f-4471-9d7f-1230542397f7', name: 'Сормовский' },
  ],
  'Новосибирск': [
    { id: '5e79bb5c-96cb-4991-a15e-e5a2fa4e69fa', name: 'Дзержинский' },
    { id: '988f844d-b510-464d-8423-67abb6bcb282', name: 'Железнодорожный' },
    { id: 'a1741247-8883-40fd-bd29-75dc6cf97a1b', name: 'Заельцовский' },
    { id: 'd177bc1e-16c6-43f1-9291-9a026647e2c0', name: 'Калининский' },
    { id: 'c6636da5-6499-4215-b7cc-127b0ff78c44', name: 'Кировский' },
    { id: '3747021c-3a90-41ab-b72d-4a407adb5a7e', name: 'Ленинский' },
    { id: '9584d403-9a40-4cee-8ff4-5c307a5a796d', name: 'Октябрьский' },
    { id: 'd89690b9-d40d-413c-b85d-16eb4902d513', name: 'Первомайский' },
    { id: 'afd9de29-ba7a-46c4-97c7-b522c0d2ec82', name: 'Советский' },
    { id: 'ff54c726-73b9-4ef0-bbdc-8e471cfee805', name: 'Центральный' },
  ],
  'Ростов-на-Дону': [
    { id: '0917a048-37ac-4bdf-8ba8-ba8447356e0e', name: 'Ворошиловский' },
    { id: '8da46810-2189-4c92-8b8f-d629dde3d3b6', name: 'Железнодорожный' },
    { id: 'abeb30e6-ce86-43a0-b60b-e276164936d5', name: 'Кировский' },
    { id: 'b92e89e5-1bd1-4a90-8b91-783488706e3f', name: 'Ленинский' },
    { id: 'fd48e1f9-b422-41ca-80a9-7167ed3307a3', name: 'Октябрьский' },
    { id: '4cd554f1-15cb-4669-911e-b78e4045284a', name: 'Первомайский' },
    { id: 'bc79f8a1-a549-4bea-ac23-3131df35962b', name: 'Пролетарский' },
    { id: 'fa32b543-bd1f-421a-9e05-82d5cd9f7d17', name: 'Советский' },
  ],
  'Сочи': [
    { id: '066da97d-662e-4514-85bb-0d9b9a9c4d52', name: 'Адлерский' },
    { id: '742f73df-357d-4c7c-a8f5-7fc2ab40a3fa', name: 'Лазаревский' },
    { id: '140c4061-7973-4196-8bc5-3847246a0099', name: 'Хостинский' },
    { id: 'cdce6d33-0b12-42a5-b4bc-1912f809c452', name: 'Центральный' },
  ],
};

// ── Helpers ────────────────────────────────────────────
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function randomDelay(minMs, maxMs) {
  const delay = minMs + Math.random() * (maxMs - minMs);
  return sleep(delay);
}

function matchesStopWord(text, stopWords) {
  if (!text) return false;
  const lower = text.toLowerCase();
  return stopWords.some((sw) => lower.includes(sw));
}

function isFiltered(place) {
  if (matchesStopWord(place.title, STOP_WORDS_NAME)) return 'stop_name';
  if (matchesStopWord(place.category, STOP_WORDS_CATEGORY)) return 'stop_category';
  if (matchesStopWord(place.website, STOP_WORDS_SITE)) return 'stop_site';
  if (place.rating !== null && place.rating < 4.0) return 'low_rating';
  return null;
}

// ── Photo download ─────────────────────────────────────
function downloadBuffer(url) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : http;
    proto.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return downloadBuffer(res.headers.location).then(resolve, reject);
      }
      if (res.statusCode >= 400) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks)));
      res.on('error', reject);
    }).on('error', reject);
  });
}

async function downloadPhotos(photoUrls, citySlug, yandexId, photosBaseDir) {
  if (!photoUrls || photoUrls.length === 0) return [];
  const dir = path.join(photosBaseDir, citySlug, yandexId);
  fs.mkdirSync(dir, { recursive: true });

  const saved = [];
  for (let i = 0; i < Math.min(photoUrls.length, 3); i++) {
    try {
      const buf = await downloadBuffer(photoUrls[i]);
      const resized = await sharp(buf)
        .resize(800, 600, { fit: 'inside', withoutEnlargement: true })
        .sharpen({ sigma: 0.5 })
        .modulate({ saturation: 1.08 })
        .webp({ quality: 82 })
        .toBuffer();
      const filename = `${i + 1}.webp`;
      fs.writeFileSync(path.join(dir, filename), resized);
      saved.push(`${citySlug}/${yandexId}/${filename}`);
    } catch (err) {
      // skip failed photo
    }
  }
  return saved;
}

// ── Captcha wait ───────────────────────────────────────
async function waitForCaptcha(page, log) {
  if (!page.url().includes('showcaptcha')) return;
  log('  CAPTCHA! Реши вручную в браузере...');
  while (page.url().includes('showcaptcha')) {
    await sleep(3000);
  }
  log('  Captcha solved');
  await sleep(3000);
}

// ── Scroll results list to load all items ──────────────
async function scrollResultsList(page, log) {
  let prevCount = 0;
  let stableRounds = 0;
  for (let i = 0; i < 40; i++) {
    const count = await page.$$eval(
      'ul.search-list-view__list > li',
      (items) => items.length
    ).catch(() => 0);

    if (count === prevCount) {
      stableRounds++;
      if (stableRounds >= 3) break;
    } else {
      stableRounds = 0;
    }
    prevCount = count;

    await page.evaluate(() => {
      const container = document.querySelector('.scroll__container');
      if (container) container.scrollBy(0, 800);
    });
    await sleep(1500 + Math.random() * 1000);
  }
  return prevCount;
}

// ── Extract org links from search results list ─────────
async function extractOrgLinksFromList(page) {
  return page.$$eval('ul.search-list-view__list > li', (items) => {
    const results = [];
    for (const li of items) {
      const link = li.querySelector('a[href*="/maps/org/"]');
      if (!link) continue;
      const href = link.getAttribute('href') || '';

      // basic info from snippet
      const titleEl = li.querySelector(
        '.search-business-snippet-view__title, .search-snippet-view__title'
      );
      const ratingEl = li.querySelector('.business-rating-badge-view__rating-text');
      const addressEl = li.querySelector('.search-business-snippet-view__address');

      const title = titleEl?.textContent?.trim() || '';
      const ratingText = ratingEl?.textContent?.trim() || '';
      const rating = ratingText ? parseFloat(ratingText.replace(',', '.')) : null;
      const address = addressEl?.textContent?.trim() || '';

      results.push({ href, title, rating, address });
    }
    return results;
  });
}

// ── Extract full card data from org page ───────────────
async function extractCardData(page) {
  return page.evaluate(() => {
    const result = {};

    // yandex_id from URL: /maps/org/name/12345678/ → 12345678
    const urlMatch = window.location.href.match(/\/org\/[^/]+\/(\d+)/);
    result.yandex_id = urlMatch ? urlMatch[1] : null;

    // Title
    const titleEl = document.querySelector(
      '.orgpage-header-view__header, .card-title-view__title-link, h1'
    );
    result.title = titleEl?.textContent?.trim() || '';

    // Address
    const addressEl = document.querySelector(
      '.orgpage-header-view__address, .business-contacts-view__address-link'
    );
    result.address = addressEl?.textContent?.trim() || '';

    // Category
    const catEl = document.querySelector(
      '.orgpage-header-view__category, .business-header-view__category'
    );
    result.category = catEl?.textContent?.trim() || '';

    // Rating
    const ratingContainer = document.querySelector(
      '.orgpage-header-view__wrapper-rating .business-rating-badge-view__rating-text'
    );
    if (ratingContainer) {
      result.rating = parseFloat(ratingContainer.textContent.trim().replace(',', '.')) || null;
    } else {
      const allRatings = document.querySelectorAll('.business-rating-badge-view__rating-text');
      result.rating = null;
      for (const el of allRatings) {
        const t = el.textContent?.trim();
        if (t && /^\d/.test(t)) {
          result.rating = parseFloat(t.replace(',', '.')) || null;
          break;
        }
      }
    }

    // Review count
    const reviewsEl = document.querySelector(
      '.business-header-rating-view__text, .business-summary-rating-badge-view__rating-count'
    );
    const reviewsText = reviewsEl?.textContent?.trim() || '';
    const reviewsMatch = reviewsText.match(/(\d[\d\s]*)/);
    result.review_count = reviewsMatch
      ? parseInt(reviewsMatch[1].replace(/\s/g, ''), 10)
      : null;

    // Phone
    const phoneEl = document.querySelector('.orgpage-phones-view__phone-number');
    result.phone = phoneEl?.textContent?.trim() || null;
    // All phones
    const phoneEls = document.querySelectorAll(
      '.orgpage-phones-view__phone-number, a[href^="tel:"]'
    );
    const phones = [];
    const seenPhones = new Set();
    phoneEls.forEach((el) => {
      let ph = el.textContent?.trim();
      if (!ph || ph.length < 6) return;
      ph = ph.replace(/Показать\s*телефон/gi, '').trim();
      if (ph && !seenPhones.has(ph)) {
        seenPhones.add(ph);
        phones.push(ph);
      }
    });
    if (!result.phone && phones.length > 0) result.phone = phones[0];
    result.phones_all = phones;

    // Website
    const siteEl = document.querySelector('.business-urls-view__link');
    result.website = siteEl?.textContent?.trim() || siteEl?.getAttribute('href') || null;

    // Coordinates from URL: ll=lng,lat or /maps/lat,lng
    const llMatch = window.location.href.match(/ll=([\d.]+)%2C([\d.]+)/);
    if (llMatch) {
      result.lng = parseFloat(llMatch[1]);
      result.lat = parseFloat(llMatch[2]);
    } else {
      result.lat = null;
      result.lng = null;
    }

    // URL
    result.yandex_url = window.location.href;

    // Photos — up to 3 from carousel
    const mediaImgs = document.querySelectorAll('.orgpage-media-view__media img.img-with-alt');
    const photoUrls = [];
    const seenUrls = new Set();
    for (const img of mediaImgs) {
      const src = img.src || '';
      const alt = (img.alt || '').toLowerCase();
      if (alt.includes('логотип') || alt.includes('logo')) continue;
      if (src.includes('static-pano') || src.includes('yastatic.net')) continue;
      if (!src.includes('avatars.mds.yandex.net')) continue;
      if ((img.naturalWidth || 0) < 200) continue;
      if (seenUrls.has(src)) continue;
      seenUrls.add(src);
      photoUrls.push(src);
      if (photoUrls.length >= 3) break;
    }
    // Fallback
    if (photoUrls.length === 0) {
      const allImgs = document.querySelectorAll('img.img-with-alt');
      for (const img of allImgs) {
        const src = img.src || '';
        const alt = (img.alt || '').toLowerCase();
        if (alt.includes('логотип') || alt.includes('logo')) continue;
        if (src.includes('static-pano') || src.includes('yastatic.net')) continue;
        if (!src.includes('avatars.mds.yandex.net')) continue;
        if ((img.naturalWidth || 0) < 200) continue;
        if (seenUrls.has(src)) continue;
        seenUrls.add(src);
        photoUrls.push(src);
        if (photoUrls.length >= 3) break;
      }
    }
    result.photo_urls = photoUrls;

    return result;
  });
}

// ── Scroll card to load contacts ───────────────────────
async function scrollCard(page) {
  try {
    const scrollable = await page.$('.scroll__container, .business-card__content, [class*="scroll"]');
    if (scrollable) {
      for (let i = 0; i < 5; i++) {
        await scrollable.evaluate((el) => el.scrollBy(0, 400));
        await sleep(500);
      }
    }
  } catch {
    await page.evaluate(() => window.scrollBy(0, 1500));
    await sleep(1000);
  }
}

// ── Click "show phone" if exists ───────────────────────
async function clickShowPhone(page) {
  try {
    const btn = await page.$('button:has-text("Показать телефон"), a:has-text("Показать телефон"), [class*="phone"] button');
    if (btn) {
      await btn.click();
      await sleep(1500);
    }
  } catch { /* noop */ }
}

// ── Progress file management ───────────────────────────
function loadProgress(filePath) {
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return { completedQueries: [], lastAreaIdx: 0, lastTypeIdx: 0 };
}

function saveProgress(filePath, progress) {
  fs.writeFileSync(filePath, JSON.stringify(progress, null, 2));
}

// ── Results file (append-safe) ─────────────────────────
function loadResults(filePath) {
  if (fs.existsSync(filePath)) {
    return JSON.parse(fs.readFileSync(filePath, 'utf-8'));
  }
  return [];
}

function saveResults(filePath, results) {
  fs.writeFileSync(filePath, JSON.stringify(results, null, 2));
}

// ── Pause/resume via stdin ─────────────────────────────
function setupPauseControl(log) {
  let paused = false;
  let resolvePause = null;

  const rl = readline.createInterface({ input: process.stdin });
  rl.on('line', (line) => {
    if (line.trim().toLowerCase() === 'pause') {
      if (!paused) {
        paused = true;
        log('PAUSED. Введи "pause" чтобы продолжить.');
      } else {
        paused = false;
        log('RESUMED.');
        if (resolvePause) {
          resolvePause();
          resolvePause = null;
        }
      }
    }
  });

  async function waitIfPaused() {
    if (!paused) return;
    await new Promise((resolve) => {
      resolvePause = resolve;
    });
  }

  return { waitIfPaused };
}

// ── Logging ────────────────────────────────────────────
function createLogger(scriptName) {
  const logsDir = path.join(__dirname, '..', 'logs');
  fs.mkdirSync(logsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const logFile = path.join(logsDir, `${scriptName}_${ts}.log`);
  const stream = fs.createWriteStream(logFile, { flags: 'a' });

  function log(msg) {
    const line = `[${new Date().toISOString().slice(11, 19)}] ${msg}`;
    console.log(line);
    stream.write(line + '\n');
  }

  function close() { stream.end(); }

  return { log, close, logFile };
}

// ── City slug for photo dirs ───────────────────────────
function citySlug(city) {
  const map = {
    'Москва': 'moscow',
    'Санкт-Петербург': 'spb',
    'Казань': 'kazan',
    'Краснодар': 'krasnodar',
    'Нижний Новгород': 'nn',
    'Новосибирск': 'novosibirsk',
    'Ростов-на-Дону': 'rostov',
    'Сочи': 'sochi',
  };
  return map[city] || city.toLowerCase().replace(/\s+/g, '_');
}

// ════════════════════════════════════════════════════════
//  createParser — фабрика парсера
// ════════════════════════════════════════════════════════
export function createParser(scriptName, cityAreas) {
  // cityAreas: { cityName: [{ id, name }, ...], ... }
  const { log, close: closeLog, logFile } = createLogger(scriptName);
  const photosBaseDir = path.join(__dirname, '..', 'scraped_photos_v2');
  const progressFile = path.join(__dirname, `${scriptName}_progress.json`);
  const resultsFile = path.join(__dirname, `${scriptName}_results.json`);

  fs.mkdirSync(photosBaseDir, { recursive: true });

  async function run() {
    log(`=== ${scriptName} ===`);
    log(`Лог: ${logFile}`);

    const { waitIfPaused } = setupPauseControl(log);

    // Build work queue: [{city, area, type}, ...]
    const queue = [];
    for (const [city, areas] of Object.entries(cityAreas)) {
      for (const area of areas) {
        for (const type of PLACE_TYPES) {
          queue.push({ city, area, type });
        }
      }
    }
    log(`Всего запросов: ${queue.length}`);

    // Load progress
    const progress = loadProgress(progressFile);
    const completedSet = new Set(progress.completedQueries || []);
    let results = loadResults(resultsFile);
    const seenYandexIds = new Set(results.map((r) => r.yandex_id));
    log(`Уже выполнено: ${completedSet.size} запросов, ${results.length} мест`);

    // Launch browser
    const browser = await chromium.launch({
      headless: false,
      args: [
        '--disable-blink-features=AutomationControlled',
        '--window-size=1200,900',
      ],
    });
    const context = await browser.newContext({
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      viewport: { width: 1200, height: 900 },
      locale: 'ru-RU',
    });
    const page = await context.newPage();

    process.on('SIGINT', async () => {
      log('\nПрервано (Ctrl+C). Сохраняю прогресс...');
      saveResults(resultsFile, results);
      saveProgress(progressFile, {
        completedQueries: [...completedSet],
      });
      await browser.close().catch(() => {});
      closeLog();
      process.exit(0);
    });

    let totalNew = 0;
    let totalFiltered = 0;
    let totalDupes = 0;
    let totalErrors = 0;

    for (let qi = 0; qi < queue.length; qi++) {
      const { city, area, type } = queue[qi];
      const queryKey = `${city}|${area.name}|${type}`;

      if (completedSet.has(queryKey)) continue;
      await waitIfPaused();

      const qIdx = `[${qi + 1}/${queue.length}]`;
      log(`${qIdx} ${city} → ${area.name} → ${type}`);

      try {
        // Search URL
        const query = `${type} ${city} ${area.name}`;
        const url = `https://yandex.ru/maps/?text=${encodeURIComponent(query)}`;
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
        await sleep(6000 + Math.random() * 4000);
        await waitForCaptcha(page, log);

        // Scroll to load all results
        const resultCount = await scrollResultsList(page, log);
        if (resultCount === 0) {
          log(`${qIdx}   0 результатов`);
          completedSet.add(queryKey);
          saveProgress(progressFile, { completedQueries: [...completedSet] });
          await randomDelay(2000, 4000);
          continue;
        }

        // Extract org links from list
        const orgLinks = await extractOrgLinksFromList(page);
        log(`${qIdx}   ${orgLinks.length} организаций в выдаче`);

        let newInQuery = 0;
        let filteredInQuery = 0;
        let dupesInQuery = 0;

        for (let oi = 0; oi < orgLinks.length; oi++) {
          await waitIfPaused();
          const org = orgLinks[oi];

          // Quick pre-filter by rating from snippet
          if (org.rating !== null && org.rating < 4.0) {
            filteredInQuery++;
            continue;
          }
          // Quick pre-filter by name stop words
          if (matchesStopWord(org.title, STOP_WORDS_NAME)) {
            filteredInQuery++;
            continue;
          }
          // Quick pre-filter by city in address snippet (avoid opening wrong-city cards)
          if (org.address) {
            const snippetAddr = org.address.toLowerCase();
            const cityLow = city.toLowerCase();
            const variants = [cityLow];
            if (city === 'Санкт-Петербург') variants.push('петербург', 'спб');
            if (city === 'Нижний Новгород') variants.push('н. новгород', 'н.новгород');
            if (city === 'Ростов-на-Дону') variants.push('ростов');
            if (!variants.some((v) => snippetAddr.includes(v))) {
              filteredInQuery++;
              continue;
            }
          }

          // Open org card
          const fullUrl = org.href.startsWith('http')
            ? org.href
            : `https://yandex.ru${org.href}`;
          try {
            await page.goto(fullUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
          } catch (navErr) {
            log(`${qIdx}   [${oi + 1}] nav error: ${navErr.message}`);
            totalErrors++;
            await randomDelay(3000, 5000);
            continue;
          }
          await sleep(5000 + Math.random() * 4000);
          await waitForCaptcha(page, log);

          // Scroll card & show phone
          await scrollCard(page);
          await clickShowPhone(page);

          // Extract data
          const data = await extractCardData(page);

          // Dedupe
          if (!data.yandex_id) {
            // try to extract from URL
            const idMatch = page.url().match(/\/org\/[^/]+\/(\d+)/);
            data.yandex_id = idMatch ? idMatch[1] : `unknown_${Date.now()}`;
          }

          if (seenYandexIds.has(data.yandex_id)) {
            dupesInQuery++;
            await randomDelay(2000, 4000);
            continue;
          }

          // City check — skip places from wrong city
          const addrLower = (data.address || '').toLowerCase();
          const cityLower = city.toLowerCase();
          // Для "Санкт-Петербург" проверяем и "Петербург" и "СПб"
          const cityVariants = [cityLower];
          if (city === 'Санкт-Петербург') cityVariants.push('петербург', 'спб');
          if (city === 'Нижний Новгород') cityVariants.push('н. новгород', 'н.новгород');
          if (city === 'Ростов-на-Дону') cityVariants.push('ростов');
          const cityMatch = cityVariants.some((v) => addrLower.includes(v));
          if (!cityMatch && addrLower.length > 5) {
            log(`${qIdx}   [${oi + 1}] skip wrong city: ${data.title} (${data.address})`);
            filteredInQuery++;
            await randomDelay(2000, 4000);
            continue;
          }

          // Full filter
          const filterReason = isFiltered(data);
          if (filterReason) {
            filteredInQuery++;
            await randomDelay(2000, 4000);
            continue;
          }

          // Check photo count
          if (!data.photo_urls || data.photo_urls.length < 1) {
            filteredInQuery++;
            await randomDelay(2000, 4000);
            continue;
          }

          // Download photos
          const slug = citySlug(city);
          const photoPaths = await downloadPhotos(
            data.photo_urls, slug, data.yandex_id, photosBaseDir
          );

          // Build result
          const place = {
            yandex_id: data.yandex_id,
            title: data.title,
            address: data.address,
            category: data.category,
            search_type: type,
            city,
            area_id: area.id,
            area_name: area.name,
            phone: data.phone,
            phones_all: data.phones_all,
            website: data.website,
            rating: data.rating,
            review_count: data.review_count,
            lat: data.lat,
            lng: data.lng,
            yandex_url: data.yandex_url,
            photo_paths: photoPaths,
            photo_count: photoPaths.length,
            scraped_at: new Date().toISOString(),
          };

          results.push(place);
          seenYandexIds.add(data.yandex_id);
          newInQuery++;
          totalNew++;

          const ratingStr = data.rating ? `★${data.rating}` : '';
          const photoStr = photoPaths.length > 0 ? `foto×${photoPaths.length}` : '';
          log(`${qIdx}   [${oi + 1}] + ${data.title?.slice(0, 35)} ${ratingStr} ${photoStr}`);

          // Save incrementally every 5 places
          if (totalNew % 5 === 0) {
            saveResults(resultsFile, results);
          }

          // Rate limit between places
          await randomDelay(8000, 15000);
        }

        log(`${qIdx}   итого: +${newInQuery} новых, ${filteredInQuery} отфильтровано, ${dupesInQuery} дублей`);
        totalFiltered += filteredInQuery;
        totalDupes += dupesInQuery;

        // Mark query completed
        completedSet.add(queryKey);
        saveProgress(progressFile, { completedQueries: [...completedSet] });
        saveResults(resultsFile, results);

        // Pause between area+type queries
        await randomDelay(15000, 25000);

      } catch (err) {
        log(`${qIdx}   ERROR: ${err.message}`);
        totalErrors++;
        // Save progress even on error
        saveProgress(progressFile, { completedQueries: [...completedSet] });
        saveResults(resultsFile, results);
        await randomDelay(10000, 20000);
      }
    }

    // Final save & summary
    saveResults(resultsFile, results);
    saveProgress(progressFile, { completedQueries: [...completedSet] });

    log('');
    log('=== ИТОГИ ===');
    log(`Новых мест: ${totalNew}`);
    log(`Отфильтровано: ${totalFiltered}`);
    log(`Дублей: ${totalDupes}`);
    log(`Ошибок: ${totalErrors}`);
    log(`Всего в файле: ${results.length}`);

    await browser.close().catch(() => {});
    closeLog();
  }

  return { run };
}
