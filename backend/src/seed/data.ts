import type { Shape } from './images.js';

/**
 * Demo catalog. Every app, developer and brand here is invented for the demo;
 * bundle ids use the reserved `com.example.*` namespace.
 */

export interface SeedCategory {
  id: string;
  kind: 'apps' | 'games';
  en: string;
  ru: string;
  sf: string;
}

export const CATEGORIES: SeedCategory[] = [
  { id: 'productivity', kind: 'apps', en: 'Productivity', ru: 'Продуктивность', sf: 'checkmark.circle' },
  { id: 'photo_video', kind: 'apps', en: 'Photo & Video', ru: 'Фото и видео', sf: 'camera' },
  { id: 'music', kind: 'apps', en: 'Music', ru: 'Музыка', sf: 'music.note' },
  { id: 'health', kind: 'apps', en: 'Health & Fitness', ru: 'Здоровье и фитнес', sf: 'heart' },
  { id: 'education', kind: 'apps', en: 'Education', ru: 'Образование', sf: 'graduationcap' },
  { id: 'utilities', kind: 'apps', en: 'Utilities', ru: 'Утилиты', sf: 'wrench.and.screwdriver' },
  { id: 'puzzle', kind: 'games', en: 'Puzzle', ru: 'Головоломки', sf: 'puzzlepiece' },
  { id: 'arcade', kind: 'games', en: 'Arcade', ru: 'Аркады', sf: 'gamecontroller' },
];

type L = [en: string, ru: string];

export interface SeedApp {
  slug: string;
  category: string;
  developer: string;
  name: string | { en: string; ru: string };
  subtitle: L;
  description: L;
  whatsNew: L;
  colors: [tintLight: string, tintDark: string, bg: string];
  rating: number;
  ratingCount: number;
  version: string;
  sizeMb: number;
  age?: string;
  badge?: 'new' | 'updated';
  shape: Shape;
  /** Ship a synthetic IPA for this app (install path demo). */
  ipa?: 'xml' | 'binary';
}

export const APPS: SeedApp[] = [
  {
    slug: 'quillstack', category: 'productivity', developer: 'Northfold Studio', name: 'Quillstack',
    subtitle: ['Notes, lists and quick ideas', 'Заметки, списки и быстрые идеи'],
    description: [
      'Quillstack keeps notes, checklists and half-formed ideas in one calm place. Stack pages, pin what matters and find anything with instant search.',
      'Quillstack собирает заметки, чек-листы и недодуманные идеи в одном спокойном месте. Складывайте страницы стопками, закрепляйте важное и находите всё мгновенным поиском.',
    ],
    whatsNew: ['Pinned stacks now sync faster.', 'Закреплённые стопки синхронизируются быстрее.'],
    colors: ['#0041DC', '#6AA2E3', '#EAF1FF'], rating: 4.8, ratingCount: 2140, version: '3.2.0', sizeMb: 48,
    badge: 'updated', shape: 'circle', ipa: 'xml',
  },
  {
    slug: 'tasklantern', category: 'productivity', developer: 'Brightmoor Labs', name: 'Tasklantern',
    subtitle: ['Tasks that light the way', 'Задачи, которые ведут вперёд'],
    description: [
      'Plan the day with a single glowing list. Tasklantern highlights the next step and gently dims everything that can wait.',
      'Планируйте день одним светящимся списком. Tasklantern подсвечивает следующий шаг и приглушает всё, что может подождать.',
    ],
    whatsNew: ['New evening review screen.', 'Новый экран вечернего обзора.'],
    colors: ['#E07A00', '#FFB054', '#FFF3E3'], rating: 4.6, ratingCount: 980, version: '2.4.1', sizeMb: 36, shape: 'triangle',
  },
  {
    slug: 'plannetto', category: 'productivity', developer: 'Orbweaver Software', name: 'Plannetto',
    subtitle: ['Calendar for busy weeks', 'Календарь для насыщенных недель'],
    description: [
      'A week view that fits on one screen. Drag blocks of time, see free slots at a glance and share plans with family.',
      'Неделя, которая помещается на один экран. Перетаскивайте блоки времени, сразу видьте свободные окна и делитесь планами с семьёй.',
    ],
    whatsNew: ['Shared calendars for families.', 'Общие календари для семьи.'],
    colors: ['#7A3FD1', '#B48CFF', '#F3ECFF'], rating: 4.5, ratingCount: 612, version: '1.9.0', sizeMb: 52,
    badge: 'new', shape: 'ring',
  },
  {
    slug: 'prismadrift', category: 'photo_video', developer: 'Velvet Fern Studio', name: 'Prismadrift',
    subtitle: ['Light leaks and film tones', 'Блики и плёночные тона'],
    description: [
      'Give photos the soft glow of old film. Mix light leaks, grain and warm tones, then save your look as a preset.',
      'Добавьте снимкам мягкое свечение старой плёнки. Смешивайте блики, зерно и тёплые тона и сохраняйте стиль как пресет.',
    ],
    whatsNew: ['Twelve new film stocks.', 'Двенадцать новых плёнок.'],
    colors: ['#D1366B', '#FF7FA6', '#FFEAF1'], rating: 4.7, ratingCount: 3320, version: '5.1.2', sizeMb: 96, shape: 'diamond',
  },
  {
    slug: 'frameloom', category: 'photo_video', developer: 'Kestrel Byte', name: 'Frameloom',
    subtitle: ['Stitch clips into stories', 'Склейка клипов в истории'],
    description: [
      'Weave short clips into a story with beat-synced cuts, titles and gentle transitions. Export in vertical or wide format.',
      'Сплетайте короткие клипы в историю: склейки в такт, титры и мягкие переходы. Экспорт в вертикальном или широком формате.',
    ],
    whatsNew: ['Auto-captions for spoken clips.', 'Автосубтитры для клипов с речью.'],
    colors: ['#0F8F7E', '#4FD1BE', '#E3FAF6'], rating: 4.4, ratingCount: 845, version: '2.0.3', sizeMb: 120, shape: 'square',
  },
  {
    slug: 'echobramble', category: 'music', developer: 'Thistlewave Audio', name: 'Echobramble',
    subtitle: ['Loops, pads and field recordings', 'Лупы, пэды и полевые записи'],
    description: [
      'Layer loops, ambient pads and your own field recordings into living soundscapes. Everything stays in tempo.',
      'Наслаивайте лупы, атмосферные пэды и собственные полевые записи в живые звуковые пейзажи. Всё остаётся в темпе.',
    ],
    whatsNew: ['Tape-stop effect and MIDI clock.', 'Эффект остановки ленты и MIDI-синхронизация.'],
    colors: ['#2E3A8C', '#8C9BFF', '#E8EBFF'], rating: 4.6, ratingCount: 1501, version: '4.0.0', sizeMb: 140,
    badge: 'updated', shape: 'ring',
  },
  {
    slug: 'tunewisp', category: 'music', developer: 'Marrowlight', name: 'Tunewisp',
    subtitle: ['Pocket tuner and metronome', 'Карманный тюнер и метроном'],
    description: [
      'A precise chromatic tuner and a metronome that never drifts. Works for guitar, violin, ukulele and voice.',
      'Точный хроматический тюнер и метроном, который не сбивается. Подходит для гитары, скрипки, укулеле и голоса.',
    ],
    whatsNew: ['Custom tunings.', 'Свои строи.'],
    colors: ['#C2410C', '#FB923C', '#FFF1E6'], rating: 4.9, ratingCount: 5120, version: '1.6.4', sizeMb: 18, shape: 'circle',
  },
  {
    slug: 'stridefern', category: 'health', developer: 'Copperleaf Health', name: 'Stridefern',
    subtitle: ['Walks, runs and gentle goals', 'Прогулки, пробежки и мягкие цели'],
    description: [
      'Track walks and runs without pressure. Stridefern sets goals that grow with you and celebrates every streak.',
      'Отслеживайте прогулки и пробежки без давления. Stridefern ставит цели, которые растут вместе с вами, и радуется каждой серии.',
    ],
    whatsNew: ['Route maps for long walks.', 'Карты маршрутов для долгих прогулок.'],
    colors: ['#2F8F2F', '#6FD36F', '#EAF8EA'], rating: 4.5, ratingCount: 2210, version: '3.0.1', sizeMb: 64, shape: 'triangle',
  },
  {
    slug: 'calmquarry', category: 'health', developer: 'Saltmeadow', name: 'Calmquarry',
    subtitle: ['Breathing breaks in a minute', 'Минута на дыхание и паузу'],
    description: [
      'One-minute breathing breaks with a soft visual guide. No accounts, no noise — just a pause when you need it.',
      'Минутные дыхательные паузы с мягкой визуальной подсказкой. Без аккаунтов и шума — просто пауза, когда она нужна.',
    ],
    whatsNew: ['Evening wind-down sessions.', 'Вечерние сессии для расслабления.'],
    colors: ['#3A6EA5', '#8FB8E8', '#EAF2FB'], rating: 4.8, ratingCount: 1870, version: '2.2.0', sizeMb: 42,
    badge: 'new', shape: 'circle',
  },
  {
    slug: 'lexiglade', category: 'education', developer: 'Owlstone Learning', name: 'Lexiglade',
    subtitle: ['Words a day, the friendly way', 'Слова каждый день — по-дружески'],
    description: [
      'Learn five new words a day with spaced repetition and tiny stories. Pick from twelve languages.',
      'Учите пять новых слов в день с интервальными повторениями и короткими историями. Двенадцать языков на выбор.',
    ],
    whatsNew: ['Story mode for beginners.', 'Режим историй для начинающих.'],
    colors: ['#8A5A00', '#E0AE4A', '#FFF6E0'], rating: 4.6, ratingCount: 1320, version: '6.3.0', sizeMb: 88, shape: 'square',
  },
  {
    slug: 'numberwood', category: 'education', developer: 'Owlstone Learning', name: { en: 'Numberwood', ru: 'Числолес' },
    subtitle: ['Math puzzles for curious kids', 'Математические задачки для любопытных'],
    description: [
      'Explore a forest where every path is a math puzzle. Adapts to the child’s level and never shows ads.',
      'Исследуйте лес, где каждая тропинка — математическая задачка. Подстраивается под уровень ребёнка и не показывает рекламу.',
    ],
    whatsNew: ['New fractions grove.', 'Новая роща дробей.'],
    colors: ['#1E7F4F', '#5FD69A', '#E6F7EE'], rating: 4.7, ratingCount: 760, version: '2.1.0', sizeMb: 74, shape: 'plus',
  },
  {
    slug: 'unitbloom', category: 'utilities', developer: 'Gearmint', name: 'Unitbloom',
    subtitle: ['Convert anything in a tap', 'Перевод величин в одно касание'],
    description: [
      'Length, weight, temperature, cooking measures and more. Type a value and every unit blooms around it.',
      'Длина, вес, температура, кухонные меры и многое другое. Введите значение — и все единицы распустятся вокруг него.',
    ],
    whatsNew: ['Cooking presets.', 'Кулинарные пресеты.'],
    colors: ['#455A64', '#9FB4BE', '#EEF2F4'], rating: 4.4, ratingCount: 430, version: '1.3.2', sizeMb: 12, shape: 'diamond',
  },
  {
    slug: 'scanmarsh', category: 'utilities', developer: 'Gearmint', name: 'Scanmarsh',
    subtitle: ['Paper to PDF, sharp and fast', 'Из бумаги в PDF — чётко и быстро'],
    description: [
      'Scan receipts, letters and notes into crisp PDFs. Edges are found automatically and text becomes searchable.',
      'Сканируйте чеки, письма и записи в чёткие PDF. Края находятся автоматически, а текст становится доступным для поиска.',
    ],
    whatsNew: ['Batch scanning.', 'Пакетное сканирование.'],
    colors: ['#0B6E99', '#5BC0EB', '#E6F5FC'], rating: 4.3, ratingCount: 690, version: '3.4.0', sizeMb: 58, shape: 'square',
  },
  {
    slug: 'skyvellum', category: 'utilities', developer: 'Cloudberry Works', name: 'Skyvellum',
    subtitle: ['Calm weather, hour by hour', 'Спокойная погода по часам'],
    description: [
      'A quiet forecast with hourly detail, rain timing and soft illustrations that follow the sky outside.',
      'Тихий прогноз с почасовыми деталями, временем дождя и мягкими иллюстрациями, которые повторяют небо за окном.',
    ],
    whatsNew: ['Rain-start alerts.', 'Уведомления о начале дождя.'],
    colors: ['#2563EB', '#7DA8FF', '#EAF0FF'], rating: 4.7, ratingCount: 2950, version: '7.0.1', sizeMb: 66,
    badge: 'updated', shape: 'circle',
  },
  // --- games ---------------------------------------------------------------
  {
    slug: 'tilegrove', category: 'puzzle', developer: 'Pebblefox Games', name: 'Tilegrove',
    subtitle: ['Slide tiles, grow a forest', 'Двигай плитки — расти лес'],
    description: [
      'Slide tiles to connect streams and let a tiny forest grow. Hundreds of hand-made levels and no timers.',
      'Двигайте плитки, соединяйте ручьи и выращивайте маленький лес. Сотни уровней ручной работы и никаких таймеров.',
    ],
    whatsNew: ['Autumn chapter with 40 levels.', 'Осенняя глава на 40 уровней.'],
    colors: ['#3F7D20', '#8BD45A', '#EEF8E6'], rating: 4.8, ratingCount: 8200, version: '2.5.0', sizeMb: 210,
    shape: 'square', ipa: 'binary',
  },
  {
    slug: 'glintmaze', category: 'puzzle', developer: 'Pebblefox Games', name: 'Glintmaze',
    subtitle: ['Bend light through mirror mazes', 'Проведи луч через зеркальные лабиринты'],
    description: [
      'Rotate mirrors and prisms to guide a beam of light home. Calm music, clever twists.',
      'Вращайте зеркала и призмы, чтобы привести луч света домой. Спокойная музыка и хитрые повороты.',
    ],
    whatsNew: ['Colour-splitting prisms.', 'Призмы, разделяющие цвета.'],
    colors: ['#6D28D9', '#A78BFA', '#F1EAFF'], rating: 4.6, ratingCount: 2400, version: '1.8.2', sizeMb: 180, shape: 'diamond',
  },
  {
    slug: 'wordmoss', category: 'puzzle', developer: 'Inkhollow', name: 'Wordmoss',
    subtitle: ['Cozy daily word grids', 'Уютные словесные сетки каждый день'],
    description: [
      'A fresh word grid every morning. Find the hidden theme, grow moss on your streak and relax.',
      'Каждое утро — новая словесная сетка. Найдите скрытую тему, выращивайте мох на своей серии и отдыхайте.',
    ],
    whatsNew: ['Russian word packs.', 'Наборы русских слов.'],
    colors: ['#9A3412', '#F59E6B', '#FFF0E8'], rating: 4.5, ratingCount: 3100, version: '3.1.0', sizeMb: 95,
    badge: 'new', shape: 'plus',
  },
  {
    slug: 'cubelark', category: 'puzzle', developer: 'Starling Forge', name: 'Cubelark',
    subtitle: ['Fold paper cubes, solve the sky', 'Складывай бумажные кубы'],
    description: [
      'Fold flat paper patterns into cubes that complete the sky above a sleepy village.',
      'Складывайте плоские выкройки в кубы, которые дополняют небо над сонной деревней.',
    ],
    whatsNew: ['Night levels.', 'Ночные уровни.'],
    colors: ['#0E7490', '#67E8F9', '#E6FBFF'], rating: 4.4, ratingCount: 900, version: '1.2.0', sizeMb: 160, shape: 'diamond',
  },
  {
    slug: 'hexapetal', category: 'puzzle', developer: 'Starling Forge', name: 'Hexapetal',
    subtitle: ['Hex flowers, calm combos', 'Шестиугольные цветы и спокойные комбо'],
    description: [
      'Match hexagonal petals into blooming flowers. Gentle combos, no lives, no rush.',
      'Собирайте шестиугольные лепестки в цветущие бутоны. Мягкие комбо, без жизней и спешки.',
    ],
    whatsNew: ['Garden decorations.', 'Украшения для сада.'],
    colors: ['#BE185D', '#F472B6', '#FFE8F3'], rating: 4.7, ratingCount: 1750, version: '2.0.0', sizeMb: 140, shape: 'ring',
  },
  {
    slug: 'rocket_turnip', category: 'arcade', developer: 'Puddlejump Interactive', name: 'Rocket Turnip',
    subtitle: ['One-tap veggie space flights', 'Овощные полёты в одно касание'],
    description: [
      'Tap to boost a brave turnip through asteroid gardens. Short runs, silly hats, endless fun.',
      'Касайтесь экрана, чтобы разогнать смелую репку сквозь астероидные огороды. Короткие забеги, смешные шляпы и бесконечное веселье.',
    ],
    whatsNew: ['Carrot co-pilot.', 'Морковка-штурман.'],
    colors: ['#B45309', '#FBBF24', '#FFF7E0'], rating: 4.6, ratingCount: 5400, version: '3.3.1', sizeMb: 230,
    age: '9+', shape: 'triangle',
  },
  {
    slug: 'glowdrift', category: 'arcade', developer: 'Puddlejump Interactive', name: 'Glowdrift Racer',
    subtitle: ['Neon drifts on night roads', 'Неоновый дрифт на ночных трассах'],
    description: [
      'Drift through glowing night roads, chain combos and chase your own ghost lap.',
      'Дрифтуйте по светящимся ночным трассам, собирайте комбо и догоняйте свой призрачный круг.',
    ],
    whatsNew: ['Harbour track and photo mode.', 'Трасса «Гавань» и фоторежим.'],
    colors: ['#1D4ED8', '#60A5FA', '#E6EEFF'], rating: 4.5, ratingCount: 4100, version: '4.2.0', sizeMb: 410,
    age: '9+', badge: 'updated', shape: 'diamond',
  },
  {
    slug: 'comet_kettle', category: 'arcade', developer: 'Tinroof Arcade', name: 'Comet Kettle',
    subtitle: ['Catch comets, brew stardust', 'Лови кометы и вари звёздную пыль'],
    description: [
      'Swing a cosmic kettle to catch falling comets and brew stardust recipes before the night ends.',
      'Раскачивайте космический чайник, ловите падающие кометы и варите рецепты из звёздной пыли до рассвета.',
    ],
    whatsNew: ['Daily recipes.', 'Ежедневные рецепты.'],
    colors: ['#7C2D12', '#FDBA74', '#FFF2E6'], rating: 4.3, ratingCount: 1200, version: '1.4.0', sizeMb: 150, shape: 'circle',
  },
  {
    slug: 'orchard_bounce', category: 'arcade', developer: 'Tinroof Arcade', name: 'Orchard Bounce',
    subtitle: ['Bounce, pick, repeat', 'Прыгай, собирай, повторяй'],
    description: [
      'Bounce between branches, pick ripe fruit and avoid grumpy wasps. Easy to learn, hard to put down.',
      'Прыгайте между ветками, собирайте спелые фрукты и уворачивайтесь от ворчливых ос. Легко начать, трудно оторваться.',
    ],
    whatsNew: ['Cherry season event.', 'Событие «Вишнёвый сезон».'],
    colors: ['#15803D', '#4ADE80', '#E8FBEF'], rating: 4.4, ratingCount: 2650, version: '2.7.3', sizeMb: 120,
    badge: 'new', shape: 'circle',
  },
  {
    slug: 'moonmoth', category: 'arcade', developer: 'Driftlantern', name: 'Moonmoth',
    subtitle: ['Glide through lantern-lit caves', 'Полёт сквозь пещеры с фонарями'],
    description: [
      'Guide a little moth through caves lit by paper lanterns. A short, beautiful journey with a hand-drawn world.',
      'Проведите маленького мотылька через пещеры, освещённые бумажными фонариками. Короткое красивое путешествие в нарисованном от руки мире.',
    ],
    whatsNew: ['Director’s commentary mode.', 'Режим с комментариями авторов.'],
    colors: ['#4338CA', '#A5B4FC', '#ECEEFF'], rating: 4.9, ratingCount: 6100, version: '1.0.5', sizeMb: 260,
    age: '12+', shape: 'ring',
  },
];

export const appId = (slug: string) => `app_${slug}`;

export interface SeedHero {
  slug: string;
  headline: L;
  title: L;
  gradient?: [string, string];
}

export interface SeedRoom {
  id: string;
  style: 'hero_carousel' | 'shelf_one' | 'shelf_two' | 'chips';
  title?: L;
  subtitle?: L;
  apps?: string[];
  hero?: SeedHero[];
  categories?: string[];
}

const games = APPS.filter((a) => CATEGORIES.find((c) => c.id === a.category)?.kind === 'games').map((a) => a.slug);
const nonGames = APPS.filter((a) => !games.includes(a.slug)).map((a) => a.slug);
const byRating = (slugs: string[]) =>
  [...slugs].sort((a, b) => APPS.find((x) => x.slug === b)!.rating - APPS.find((x) => x.slug === a)!.rating);

export const STOREFRONT: Record<'today' | 'games' | 'apps', SeedRoom[]> = {
  today: [
    {
      id: 'room_hero_today',
      style: 'hero_carousel',
      hero: [
        { slug: 'quillstack', headline: ['Editors’ pick', 'Выбор редакции'], title: ['Order for your thoughts', 'Порядок в мыслях'], gradient: ['#0041DC', '#92BDEF'] },
        { slug: 'moonmoth', headline: ['New game', 'Новая игра'], title: ['Into the lantern caves', 'В пещеры фонарей'] },
        { slug: 'calmquarry', headline: ['Take a breath', 'Передышка'], title: ['One minute of calm', 'Минута спокойствия'] },
        { slug: 'prismadrift', headline: ['Update', 'Обновление'], title: ['Film tones, reloaded', 'Плёнка снова в деле'] },
        { slug: 'tilegrove', headline: ['Puzzle of the week', 'Головоломка недели'], title: ['Grow a forest tile by tile', 'Лес из плиток'] },
      ],
    },
    {
      id: 'room_today_new',
      style: 'shelf_one',
      title: ['New & Updated', 'Новое и обновлённое'],
      subtitle: ['Fresh releases from our catalog', 'Свежие релизы каталога'],
      apps: [...APPS.filter((a) => a.badge).map((a) => a.slug), ...APPS.filter((a) => !a.badge).map((a) => a.slug)],
    },
    {
      id: 'room_today_editors',
      style: 'shelf_two',
      title: ['Editors’ Choice', 'Выбор редакции'],
      apps: ['quillstack', 'tunewisp', 'moonmoth', 'skyvellum', 'tilegrove', 'echobramble'],
    },
    { id: 'room_today_categories', style: 'chips', title: ['Categories', 'Категории'], categories: CATEGORIES.map((c) => c.id) },
    {
      id: 'room_today_essentials',
      style: 'shelf_one',
      title: ['Everyday Essentials', 'На каждый день'],
      apps: ['quillstack', 'tasklantern', 'plannetto', 'unitbloom', 'scanmarsh', 'skyvellum', 'calmquarry', 'stridefern'],
    },
  ],
  games: [
    {
      id: 'room_hero_games',
      style: 'hero_carousel',
      hero: [
        { slug: 'glowdrift', headline: ['Big update', 'Большое обновление'], title: ['Drift the harbour at night', 'Ночной дрифт в гавани'] },
        { slug: 'hexapetal', headline: ['Relax', 'Отдых'], title: ['Puzzles in full bloom', 'Головоломки в цвету'] },
        { slug: 'rocket_turnip', headline: ['Arcade', 'Аркада'], title: ['The bravest turnip in space', 'Самая смелая репка в космосе'] },
      ],
    },
    { id: 'room_games_top', style: 'shelf_one', title: ['Top Games', 'Популярные игры'], apps: byRating(games) },
    {
      id: 'room_games_new',
      style: 'shelf_two',
      title: ['Just Arrived', 'Новинки'],
      apps: ['wordmoss', 'orchard_bounce', 'glowdrift', 'moonmoth'],
    },
    {
      id: 'room_games_categories',
      style: 'chips',
      title: ['Game Categories', 'Категории игр'],
      categories: CATEGORIES.filter((c) => c.kind === 'games').map((c) => c.id),
    },
  ],
  apps: [
    {
      id: 'room_hero_apps',
      style: 'hero_carousel',
      hero: [
        { slug: 'skyvellum', headline: ['Updated', 'Обновлено'], title: ['Know when the rain starts', 'Узнайте, когда начнётся дождь'] },
        { slug: 'echobramble', headline: ['Create', 'Творчество'], title: ['Sound from everyday noise', 'Музыка из повседневных звуков'] },
        { slug: 'lexiglade', headline: ['Learn', 'Учёба'], title: ['Five words a day', 'Пять слов в день'] },
        { slug: 'scanmarsh', headline: ['Tip', 'Совет'], title: ['A scanner in your pocket', 'Сканер в кармане'] },
      ],
    },
    { id: 'room_apps_top', style: 'shelf_one', title: ['Top Apps', 'Лучшие приложения'], apps: byRating(nonGames) },
    {
      id: 'room_apps_work',
      style: 'shelf_two',
      title: ['Get Things Done', 'Для работы'],
      apps: ['quillstack', 'tasklantern', 'plannetto', 'scanmarsh', 'unitbloom'],
    },
    {
      id: 'room_apps_categories',
      style: 'chips',
      title: ['App Categories', 'Категории приложений'],
      categories: CATEGORIES.filter((c) => c.kind === 'apps').map((c) => c.id),
    },
    {
      id: 'room_apps_creative',
      style: 'shelf_one',
      title: ['For Creators', 'Для творчества'],
      apps: ['prismadrift', 'frameloom', 'echobramble', 'tunewisp'],
    },
  ],
};
