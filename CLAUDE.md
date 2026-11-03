# iStore — инструкции для Claude

Общение с пользователем, документация, комментарии и сообщения коммитов — **на русском**.

Перед работой прочитай [docs/HANDOFF.md](docs/HANDOFF.md): там текущее состояние, принятые решения и следующие шаги.

## Проект

iStore — магазин iOS-приложений по подписке вне App Store. По UX, визуальному стилю и архитектуре повторяет DDE Store 2.1.0. Каталог: собственные и лицензированные приложения. Установка — через OTA-манифест (`itms-services://`).

| Путь | Что это |
|---|---|
| `docs/SPEC.md` | ТЗ: решения, этапы, палитра, архитектура |
| `docs/API.md` | **Контракт API — единый источник правды** для бэкенда и клиента. Любое изменение API сначала вносится сюда |
| `docs/HANDOFF.md` | Статус, решения, известные ограничения, план |
| `backend/` | Node 22 + TypeScript (ESM, strict), Fastify 5, zod, Drizzle ORM; PostgreSQL в продакшене, PGlite (Postgres в WASM) в dev и тестах |
| `ios/` | Swift, программный UIKit, iOS 15+, XcodeGen (`project.yml`); `.xcodeproj` в git не хранится |
| `deploy/` | Docker Compose для VPS: api + PostgreSQL + Caddy (Let's Encrypt) |
| `.github/workflows/` | CI: `backend.yml` (тесты + Docker-образ), `ios.yml` (сборка и тесты на macOS) |

## Команды

Бэкенд (`cd backend`):

```bash
npm ci                 # зависимости
npm run typecheck      # tsc --noEmit
npm test               # vitest, у каждого файла свой PGlite в памяти
npm run seed           # демо-каталог; ПОЛНОСТЬЮ стирает базу и storage; dev-код DEMO-DEMO-0001
npm run dev            # http://localhost:8080
npm run db:generate    # миграция из src/db/schema.ts → drizzle/
```

iOS собирается только в CI (macOS). Локально проверяются ключи локализации: `node ios/scripts/check-l10n.mjs`.

## Среда разработки пользователя

- Windows 10; Git Bash и PowerShell; Node.js 22, npm 10.
- **Нет:** Xcode/Swift, Docker, PostgreSQL, `gh`. `python` — заглушка Windows Store.
- Код Swift нельзя скомпилировать локально. Пиши консервативно, проверяй доступность API для iOS 15, после push смотри CI.

## CI и чтение ошибок без логина

Логи Actions GitHub показывает только авторизованным, а аннотации доступны через публичный API. Шаг `Report build errors as annotations` в `ios.yml` дублирует ошибки `xcodebuild` в аннотации.

```bash
R=Vladpryanik11/xstorexAPP
curl -s "https://api.github.com/repos/$R/actions/runs?per_page=5"                # запуски
curl -s "https://api.github.com/repos/$R/actions/runs/<run_id>/jobs"              # шаги и job id
curl -s "https://api.github.com/repos/$R/check-runs/<job_id>/annotations"         # ошибки
```

Без токена лимит — 60 запросов в час: опрашивай не чаще раза в 45–60 секунд.

## Конвенции

- **API:** JSON в snake_case, ошибки — `{"error":{"code","message"}}`, курсорная пагинация, ETag и `X-Catalog-Revision` на каталоге (подробно в API.md).
- **Бэкенд:** модули по доменам в `src/modules/*`, общее — в `src/lib`, `buildApp(config)` для тестов через `app.inject()`. Новый код покрывай тестами.
- **iOS:**
  - режим Swift 5 + `SWIFT_STRICT_CONCURRENCY=targeted`, код пишется concurrency-корректно (`actor` для I/O, `@MainActor` для UI);
  - без сторонних зависимостей;
  - никаких захардкоженных строк: ключи в `en.lproj` и `ru.lproj` должны совпадать;
  - API новее iOS 15 — только под `#available`, стекло iOS 26 — под `#if compiler(>=6.2)`.
- **Git:**
  - глобальные `user.name` и `user.email` на машине не заданы. Коммить с `git -c user.name="pranicman" -c user.email="pranicman@gmail.com" commit …`, если пользователь не настроит иначе;
  - в конце сообщения коммита: `Co-Authored-By: Claude <noreply@anthropic.com>`;
  - коммить и пушить только по просьбе пользователя;
  - никогда не коммить `*.ipa`, `*.p12`, `*.mobileprovision`, `.env`.

## Грабли, на которые уже наступили

- Правила `.gitignore` пиши с `/` в начале. Строка `storage/` скрыла исходники `backend/src/storage/`, и CI упал.
- В SDK iOS 18 у `UIViewController` есть свойство `tab`. Не называй так свои свойства, проверяй и другие имена UIKit (`state`, `configuration`).
- PGlite однопроцессный: перед `npm run seed` останови `npm run dev`.
- Остановка задачи с `npx tsx …` не убивает дочерний `node`. Ищи процесс по порту (`Get-NetTCPConnection -LocalPort 8080`) и останавливай только его PID. Никогда не используй `taskkill /IM node.exe`.
- `install_id` должен быть валидным UUID (RFC 4122): иначе `400 invalid_request`.

## Рамки проекта

- Не входит в проект: раздача сертификатов подписи с сервера на устройства, подпись IPA на устройстве такими сертификатами, защита от переподписи в варианте DDE Store. Предыдущие попытки разобрать или описать этот механизм останавливал защитный фильтр. Не пытайся его воспроизвести.
- Реализованная модель установки: IPA подписан владельцем магазина (`PreSignedProvider`), сервер отдаёт грант, OTA-манифест и IPA по HTTPS.
- Бренд, тексты и иконки — свои. Ассеты и тексты оригинала не копируются.
