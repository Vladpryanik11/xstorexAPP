# iStore — бэкенд (этап 1)

Node.js 22 + TypeScript (ESM, strict), Fastify 5, zod, Drizzle ORM. В разработке и тестах база — PGlite (PostgreSQL в WASM, внутри процесса), в продакшене — PostgreSQL через `DATABASE_URL`. Docker и установленный Postgres не нужны.

Контракт API — [`../docs/API.md`](../docs/API.md), ТЗ — [`../docs/SPEC.md`](../docs/SPEC.md).

## Быстрый старт

```bash
cd backend
npm install
npm run seed     # демо-каталог: 24 вымышленных приложения, картинки, коды активации
npm run dev      # http://localhost:8080, перезапуск при изменениях
```

`npm run seed` **полностью очищает** базу и папки `storage/static`, `storage/builds`, потом печатает:
- dev-код `DEMO-DEMO-0001` (план «1 месяц», 30 дней) и ещё 5 случайных кодов;
- готовый dev-токен аккаунта `acc_dev` для `curl`.

PGlite держит каталог `.data/pglite` эксклюзивно: перед `npm run seed` остановите `npm run dev`.

```bash
# витрина
curl -H "Authorization: Bearer <dev-токен>" -H "Accept-Language: ru" "http://localhost:8080/api/v1/groupings?tab=today"

# вход по коду, как это делает клиент
curl -X POST -H "Content-Type: application/json" \
  -d '{"activation_code":"DEMO-DEMO-0001","device":{"install_id":"6f1c2f8e-6a52-4c39-9a51-3d0f1f0c2b7a","model":"iPhone16,2","os_version":"18.1","locale":"ru_RU"}}' \
  http://localhost:8080/api/v1/app/activate

# установка: грант → манифест → IPA (у app_quillstack и app_tilegrove есть синтетические IPA)
curl -X POST -H "Authorization: Bearer <токен>" -H "Content-Type: application/json" \
  -d '{"app_id":"app_quillstack"}' http://localhost:8080/api/v1/catalog/installs

# живой каталог
curl -N -H "Authorization: Bearer <токен>" "http://localhost:8080/api/v1/catalog/stream?since=0"
```

## Скрипты

| Скрипт | Что делает |
|---|---|
| `npm run dev` | `tsx watch src/server.ts` |
| `npm run build` / `npm start` | сборка в `dist/` и запуск `node dist/server.js` |
| `npm test` | vitest; каждый файл поднимает свой PGlite в памяти и временное хранилище |
| `npm run typecheck` | `tsc --noEmit` для `src` и `test` |
| `npm run seed` | демо-данные (см. выше) |
| `npm run db:generate` | `drizzle-kit generate`: SQL-миграция из `src/db/schema.ts` в `drizzle/` |

Миграции из `drizzle/` применяются автоматически при старте сервера и seed (PGlite и `pg`).

## Переменные окружения

Сервер читает `.env` в папке `backend` (пример — [`.env.example`](.env.example)).

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `PORT` | `8080` | порт HTTP |
| `HOST` | `0.0.0.0` | адрес прослушивания |
| `PUBLIC_BASE_URL` | `http://localhost:$PORT` | внешний адрес: из него строятся `icon_url`, `manifest_url`, URL IPA |
| `ADMIN_TOKEN` | — | Bearer-токен `/admin/v1` (≥ 16 символов). Не задан — админ-API отвечает `503 admin_disabled` |
| `DATABASE_URL` | — | PostgreSQL. Пусто — PGlite в `PGLITE_DIR` |
| `PGLITE_DIR` | `.data/pglite` | данные PGlite |
| `STORAGE_DIR` | `./storage` | файловое хранилище (`static/**` — картинки, `builds/**` — IPA) |
| `LOG_LEVEL` | `info` | `fatal`…`trace`, `silent` |
| `GRANT_SECRET` | случайный при старте | HMAC-секрет токенов установочных грантов. В продакшене задайте, иначе ссылки установки умирают при рестарте |
| `MAX_UPLOAD_BYTES` | `2147483648` | лимит загрузки IPA (2 ГБ) |
| `GRANT_TTL_SECONDS` | `1800` | срок жизни гранта |
| `SSE_PING_MS` | `25000` | период `: ping` в SSE |
| `CATALOG_JOURNAL_LIMIT` | `10000` | сколько последних изменений хранить; более старый `since` → `reset` |
| `CATALOG_POLL_MS` | `5000` | перечитывать журнал при подключённых SSE-клиентах (нужно, если инстансов API несколько) |
| `ACTIVATE_RATE_LIMIT_MAX` / `_WINDOW_MS` | `10` / `60000` | лимит `POST /app/activate` с одного IP |
| `RENEW_URL` | — | страница продления; в `Account.renew_url` добавляется `?acc=<id>` |
| `TRUST_PROXY` | `false` | доверять `X-Forwarded-*` (за reverse proxy) |

## Структура

```
src/
  app.ts              buildApp(config, deps) — фабрика Fastify (её используют тесты)
  server.ts           запуск, .env, graceful shutdown
  config.ts           переменные окружения (zod)
  context.ts          AppContext: config, db, storage, signing, bus, URL-хелперы
  db/                 schema.ts (Drizzle pg-core), index.ts (PGlite | pg + миграции)
  lib/                errors, etag, pagination, png, plist, ipa, range, i18n, crypto, validation
  storage/            BlobStorage (интерфейс, TODO S3) и LocalBlobStorage
  signing/            SigningProvider и PreSignedProvider (IPA уже подписан → грант сразу ready)
  modules/
    auth/             /app/activate (rate limit), /app/sign-out, Bearer-гарды
    client/           profile, store-state, version, events, push-token
    catalog/          groupings, «Показать все», карточка, версии, категории, changes, SSE, /static
    search/           поиск, подсказки, «Запросить приложение», исправление раскладки
    installs/         гранты, OTA-манифест, раздача IPA с Range
    admin/            /admin/v1: приложения, билды (multipart), витрины, категории, коды, состояние
  seed/               демо-каталог, PNG-рендер, синтетический IPA
test/                 vitest + app.inject() (SSE — через реальный порт)
drizzle/              SQL-миграции
```

Ключевые решения:
- **Ревизия каталога** — счётчик в строке `store_state`; его увеличение и запись в `catalog_changes` идут в одной транзакции, поэтому ревизии идут без пропусков и в порядке коммита. После коммита `CatalogBus` перечитывает журнал и рассылает события SSE-подключениям.
- **Токены** — 32 случайных байта (base64url); в базе только SHA-256. Коды активации хранятся как SHA-256 нормализованного кода (плюс последние 4 символа для поддержки).
- **Токен гранта** — HMAC от `install_id` (`GRANT_SECRET`), в базе только его SHA-256; живёт 30 минут.
- **Поиск** — по `search_text` (имя, подзаголовок, разработчик на обоих языках), который приложение складывает само (`ё → е`, нижний регистр). Так кириллица ищется без учёта регистра при любой локали БД.
- **Безопасность** — CORS не подключён; токены, коды и `?t=` вырезаются из логов; все входные данные проходят через zod; ключи хранилища — только `[A-Za-z0-9._-]`-сегменты без ведущей точки, плюс проверка, что путь не выходит из корня; админ-авторизация проверяется в `onRequest`, до чтения тела.

## Админ-API: пример загрузки билда

```bash
curl -X POST -H "Authorization: Bearer $ADMIN_TOKEN" \
  -F ipa=@MyApp.ipa -F notes="Исправления" \
  http://localhost:8080/admin/v1/apps/app_quillstack/builds
```

Сервер считает SHA-256 и размер, достаёт `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `MinimumOSVersion` из `Payload/*.app/Info.plist` (XML или бинарный plist). Если `bundle_id` приложения уже задан и не совпадает — `409 bundle_id_mismatch`.

## OTA-установка на реальном устройстве

iOS ставит приложение по `itms-services://` только если **манифест и IPA отдаются по HTTPS с валидным, доверенным сертификатом** (самоподписанный не подойдёт), а IPA подписан сертификатом владельца магазина (ad hoc с UDID устройства или Enterprise). Синтетические IPA из seed — просто zip для проверки цепочки до манифеста, на устройство они не встанут.

Варианты HTTPS:
- туннель к локальному серверу (например, cloudflared или аналог), его адрес — в `PUBLIC_BASE_URL`;
- свой домен и reverse proxy (nginx/Caddy) с сертификатом Let's Encrypt; тогда `PUBLIC_BASE_URL=https://api.ваш-домен`, `TRUST_PROXY=true`.

После смены `PUBLIC_BASE_URL` перезапустите сервер: все URL в ответах строятся из него.

## Ограничения этапа 1

- Подпись только `PreSignedProvider`; адаптер zsign и S3-хранилище — этап 2 (есть интерфейсы).
- PGlite однопроцессный: для нескольких инстансов используйте PostgreSQL (`DATABASE_URL`).
- Без `GRANT_SECRET` ссылки установки перестают работать после перезапуска.
