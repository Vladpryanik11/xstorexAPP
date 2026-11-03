# Xstore API v1 — контракт текущего backend

Общий API для backend и нативного iOS-клиента Xstore. Ниже описано то, что уже реализовано; новые маршруты проектируются здесь до разработки.

## Общие правила

- Базовый путь: `/api/v1`. Админ-API: `/admin/v1`.
- JSON в **snake_case**. Клиент декодирует его через `.convertFromSnakeCase`. Даты — ISO 8601 UTC (`2026-11-02T12:00:00Z`), размеры — байты (integer).
- Заголовки запроса:
  - `Authorization: Bearer <token>` — на всех защищённых маршрутах (отмечены 🔒).
  - `Accept-Language: ru` или `en`. Сервер отдаёт локализованные поля, если они есть, иначе `en`.
  - `X-Client-Build: <CFBundleVersion>`, `X-Install-Id: <uuid>` — UUID, который клиент генерирует при первом запуске и хранит в Keychain.
- Ошибка — всегда тело `{"error": {"code": "snake_case_code", "message": "Человекочитаемо"}}` и HTTP-статус:
  - `400 invalid_request`, `401 unauthorized`, `403 account_inactive`, `404 not_found`, `409 conflict`, `429 rate_limited` (с `Retry-After`), `500 internal`.
  - На `401` клиент очищает токен и показывает окно входа.
- Пагинация курсорная: `?cursor=<opaque>&limit=<1..50>` (по умолчанию 20). Ответ: `{"items": [...], "next_cursor": "..." | null}`.
- Кэширование: `GET`-ответы каталога отдают `ETag`. На `If-None-Match` с тем же значением сервер отвечает `304`. Ответы каталога несут заголовок `X-Catalog-Revision: <int>`.

## Общие схемы

```jsonc
// AppSummary — строка полки, результат поиска
{
  "id": "app_7f3k2",            // string, стабильный
  "name": "Lumen Notes",
  "subtitle": "Заметки и списки",
  "icon_url": "https://.../icon.png",
  "category": { "id": "productivity", "name": "Продуктивность" },
  "rating": 4.7,                // number | null
  "rating_count": 1280,         // integer | null
  "version": "3.2.0",
  "size_bytes": 48211968,
  "min_os": "15.0",
  "tint_light": "#0041DC",      // акцент карточки в светлой теме
  "tint_dark": "#6AA2E3",
  "bg_color": "#EAF1FF",        // фон hero-шапки
  "badge": "new" | "updated" | null,
  "availability": "available" | "unavailable"
}

// CatalogApp — карточка приложения: все поля AppSummary плюс:
{
  "description": "…",
  "whats_new": "…" | null,
  "developer": "Lumen Labs",
  "bundle_id": "com.lumenlabs.notes",
  "age_rating": "4+",
  "languages": ["RU", "EN"],
  "released_at": "2026-10-20T10:00:00Z",
  "updated_at": "2026-10-28T10:00:00Z",
  "screenshots": [{ "url": "https://…", "width": 1290, "height": 2796 }],
  "info": [{ "label": "Разработчик", "value": "Lumen Labs" }],
  "similar": [/* AppSummary, до 10 */]
}

// Room — секция витрины
{
  "id": "room_hero_today",
  "style": "hero_carousel" | "shelf_one" | "shelf_two" | "chips",
  "title": "Выбор редакции" | null,
  "subtitle": "…" | null,
  "items": [/* AppSummary; для hero_carousel до 8, shelf_one до 12, shelf_two до 8 */],
  "hero": [/* только для hero_carousel: HeroCard[] вместо items */],
  "categories": [/* только для chips: {id, name, sf_symbol}[] */],
  "has_more": true              // показывать «Показать все»
}

// HeroCard
{
  "app": { /* AppSummary */ },
  "headline": "Новое",
  "title": "Порядок в мыслях",
  "image_url": "https://…",     // широкая картинка 16:9
  "gradient": ["#0041DC", "#92BDEF"]
}

// Account
{
  "id": "acc_…",
  "display_name": "Устройство Ирины" | null,
  "plan": { "id": "month", "name": "1 месяц", "period_months": 1 },
  "status": "active" | "expired" | "suspended",
  "expires_at": "2026-12-02T00:00:00Z" | null,
  "renew_url": "https://istore.example/renew?acc=…" | null,
  "created_at": "…"
}
```

## Auth

| Метод и путь | Тело / параметры | Ответ |
|---|---|---|
| `POST /app/activate` | `{"activation_code": "ABCD-EFGH-JKLM", "device": {"install_id": "uuid", "model": "iPhone16,2", "os_version": "18.1", "locale": "ru_RU"}}` | `200 {"token": "…", "account": Account}`. Ошибки: `404 invalid_code`, `409 code_used`, `403 account_inactive` |
| `POST /app/sign-out` 🔒 | — | `204`, токен отзывается |

Код активации нормализуется: верхний регистр, без пробелов и дефисов. На одном коде можно активировать одно устройство. Повторная активация того же `install_id` тем же кодом возвращает новый токен (идемпотентно), другого — `409 code_used`.

## Client

| Метод и путь | Ответ |
|---|---|
| `GET /client/profile` 🔒 | `{"account": Account, "device": {"id", "model", "os_version", "install_id_last4"}, "client": {"locale", "app_build", "last_seen"}}` |
| `GET /client/store-state` (публичный) | `{"state": "open" \| "closed", "closed": {"title", "message", "reopens_at" \| null, "links": [{"title", "url"}]} \| null}` |
| `GET /client/version?build=<int>` (публичный) | `{"latest_version": "1.2.0", "latest_build": 120, "min_supported_build": 100, "update_available": true, "mandatory": false, "release_notes": "…", "update_url": "itms-services://…" \| null}`. `mandatory = build < min_supported_build` |
| `POST /client/events` 🔒 | `{"events": [{"kind": "install.step" \| "net.error" \| "app.launch", "ts": "…", "props": {…}}]}` (до 100 событий) → `202` |
| `POST /client/push-token` 🔒 | `{"apns_token": "hex", "apns_env": "sandbox" \| "production", "locale", "tz_offset_minutes"}` → `204` (этап 2 использует) |

## Catalog

| Метод и путь | Ответ |
|---|---|
| `GET /groupings?tab=today\|games\|apps` 🔒 | `{"tab": "today", "revision": 42, "rooms": [Room]}` + `ETag` |
| `GET /groupings/{room_id}?cursor&limit` 🔒 | `{"room": {"id", "title", "style"}, "items": [AppSummary], "next_cursor"}` — экран «Показать все» |
| `GET /catalog/apps/{id}` 🔒 | `CatalogApp` + `ETag`. Снятое приложение — `404 not_found` |
| `GET /catalog/apps/{id}/versions?cursor&limit` 🔒 | `{"items": [{"version", "build", "released_at", "notes", "size_bytes"}], "next_cursor"}` |
| `GET /catalog/categories/{id}?cursor&limit` 🔒 | `{"category": {"id", "name"}, "items": [AppSummary], "next_cursor"}` — экран категории из чипа |
| `GET /catalog/changes?since=<rev>&limit=<1..500>` 🔒 | `{"revision": 45, "changes": [Change], "has_more": false, "reset": false}`. Если `since` слишком старый (журнал обрезан), сервер отвечает `reset: true` и пустым `changes`: клиент перечитывает витрину |
| `GET /catalog/stream?since=<rev>` 🔒 | SSE, см. ниже |

```jsonc
// Change
{ "revision": 44, "kind": "app_upsert" | "app_removed" | "rooms_changed",
  "app_id": "app_…" | null, "app": AppSummary | null }
```

**SSE `/catalog/stream`**: `Content-Type: text/event-stream`. Каждое событие несёт `id: <revision>`; клиент переподключается с `Last-Event-ID` или `?since=`.
- `event: hello` / `data: {"revision": 45}` — сразу после подключения;
- `event: change` / `data: Change` — по одному на изменение (сначала догоняющие с `since`);
- `event: reset` / `data: {"revision": 45}` — клиент перечитывает витрину;
- комментарий `: ping` каждые 25 секунд.

## Search

| Метод и путь | Ответ |
|---|---|
| `GET /search?q=<text>&cursor&limit` 🔒 | `{"items": [AppSummary], "next_cursor", "corrected_query": "…" \| null}`. Поиск по имени, подзаголовку, разработчику, без учёта регистра |
| `GET /search/hints?q=<text>` 🔒 | `{"hints": [{"text": "lumen notes", "app_id": "app_…" \| null}]}` (до 8) |
| `POST /search/requests` 🔒 | `{"query": "…", "note": "…" \| null}` → `202` |

## Installs

| Метод и путь | Ответ |
|---|---|
| `POST /catalog/installs` 🔒 | `{"app_id": "…", "version": "3.2.0" \| null}` → `201 InstallGrant`. Ошибки: `404 not_found`, `403 account_inactive`, `409 no_build` (нет IPA для версии) |
| `GET /catalog/installs/{install_id}` 🔒 | `InstallGrant` (для опроса, пока `status = preparing`) |
| `GET /catalog/installs/{install_id}/manifest.plist?t=<token>` (публичный, по токену гранта) | XML-манифест OTA (`items[0].assets`: `software-package`, `display-image`, `full-size-image`; `metadata`: `bundle-identifier`, `bundle-version`, `kind=software`, `title`) |
| `GET /catalog/installs/{install_id}/app.ipa?t=<token>` (публичный, по токену гранта) | IPA, поддерживает `Range` |
| `POST /catalog/installs/{install_id}/events` 🔒 | `{"stage": "preparing" \| "ready" \| "handing_off" \| "installing" \| "failed", "error_code": "…" \| null}` → `204` |

```jsonc
// InstallGrant
{
  "install_id": "ins_…",
  "app_id": "app_…",
  "version": "3.2.0",
  "status": "preparing" | "ready" | "failed",
  "error_code": null,
  "manifest_url": "https://api.istore.example/api/v1/catalog/installs/ins_…/manifest.plist?t=…" | null,
  "itms_url": "itms-services://?action=download-manifest&url=<urlencoded manifest_url>" | null,
  "size_bytes": 48211968,
  "sha256": "hex",
  "expires_at": "…"           // грант живёт 30 минут
}
```

Сейчас `PreSignedProvider` сразу возвращает `status = ready` для загруженного IPA: фактической серверной подписи ещё нет. Серверная подпись и переподпись любых загруженных IPA — обязательная задача Xstore. Нативный iOS-клиент открывает `itms_url` через `UIApplication.shared.open`. `manifest_url` и IPA должны отдаваться по HTTPS с валидным сертификатом (требование iOS). Базовый URL задаёт `PUBLIC_BASE_URL`.

## Уточнения по реализации этапа 1

Решения, принятые при реализации бэкенда. Обязательны и для клиента.

- **Типы.** `items[].build` в истории версий — **строка** (CFBundleVersion). `latest_build` и `min_supported_build` в `/client/version` — целые числа.
- **Room.** Массивы `items`, `hero`, `categories` присутствуют всегда; где не нужны — пустые. У `hero_carousel` заполнены и `hero`, и `items`. `has_more = true`, если приложений больше лимита стиля (12 для `shelf_one`, 8 для `shelf_two`).
- **Истёкшая подписка.** При `status = expired` каталог, поиск и установки отвечают `403 account_inactive`, а профиль, sign-out, события и push-токен продолжают работать. Клиент на `403 account_inactive` показывает окно продления.
- **Коды ошибок сверх перечисленных выше:**
  - `401 grant_expired` — грант установки истёк, нужен новый;
  - `409 not_ready`, `409 no_build`, `409 bundle_id_mismatch`, `409 room_id_taken`;
  - `400 invalid_ipa`, `413 payload_too_large`, `416` (неверный Range), `503 admin_disabled`.
- **SSE.** У `hello` поле `id` равно присланному `since`. Курсор клиент двигает только по `change` и `reset`. Если приложение изменили, а затем сняли с публикации, приходит `app_removed`.
- **`/client/version`** требует `?build=` или заголовок `X-Client-Build`, иначе отвечает `400`.
- **`corrected_query`** на этапе 1 — только исправление раскладки клавиатуры (RU ↔ EN).
- **`install_id`** — валидный UUID (`UUID().uuidString` подходит).
- **Админ-API.** Текстовые поля приложения принимают строку или `{"en": "…", "ru": "…"}`. Дополнительно есть `GET /admin/v1/apps/{id}` и `PUT /admin/v1/categories/{id}`.

## Admin `/admin/v1` (заголовок `Authorization: Bearer <ADMIN_TOKEN>`)

| Метод и путь | Назначение |
|---|---|
| `POST /apps`, `PATCH /apps/{id}`, `DELETE /apps/{id}` | CRUD приложений (DELETE = снять с публикации). Каждое изменение увеличивает ревизию |
| `POST /apps/{id}/builds` (multipart: `ipa`, поля `version`, `build`, `notes`) | Сейчас: загрузка IPA без переподписи; сервер считает `sha256` и `size_bytes`, читает `CFBundleIdentifier` и `CFBundleShortVersionString` из `Info.plist`. Требуется: серверная подпись загруженного IPA и выбор сертификата/provisioning profile |
| `PUT /storefront/{tab}` | Полная замена комнат вкладки: `{"rooms": [{"id", "style", "title", "subtitle", "app_ids": [], "hero": [], "category_ids": []}]}` |
| `POST /activation-codes` | `{"count": 10, "plan_id": "month"}` → `{"codes": ["ABCD-EFGH-JKLM", …]}` |
| `PUT /store-state` | `{"state": "open" \| "closed", "closed": {…}}` |
| `PUT /client-version` | `{"latest_version", "latest_build", "min_supported_build", "release_notes", "update_url"}` |
