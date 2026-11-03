# Xstore

Магазин iOS-приложений по подписке: витрина в стиле App Store, установка по воздуху (OTA), аккаунт по коду активации. В каталоге любые приложения, сторонние IPA

Сначала сайт Xstore с загрузкой и серверной подписью IPA, затем Telegram Mini App. Сейчас в репозитории готова базовая версия backend и нативного iOS-клиента; полноценного сайта и серверной подписи пока нет.

| Папка | Что внутри |
|---|---|
| [docs/HANDOFF.md](docs/HANDOFF.md) | Текущее состояние, решения, план — начинать отсюда |
| [CLAUDE.md](CLAUDE.md) | Инструкции для Claude Code: команды, среда, конвенции, грабли |
| [docs/SPEC.md](docs/SPEC.md) | ТЗ: решения, этапы, визуальный стиль, архитектура |
| [docs/API.md](docs/API.md) | Контракт API v1, общий для бэкенда и клиента |
| [backend/](backend/) | Node.js 22 + TypeScript, Fastify, Drizzle, PostgreSQL / PGlite |
| [ios/](ios/) | Swift, UIKit, iOS 15+, проект генерирует XcodeGen |
| [deploy/](deploy/) | Деплой на VPS: Docker Compose (бэкенд + PostgreSQL + Caddy с HTTPS), инструкция |
| [.github/workflows/](.github/workflows/) | CI: тесты бэкенда и проверка Docker-образа (Ubuntu), сборка и тесты iOS (macOS) |

## Быстрый старт

Бэкенд (Windows, macOS, Linux; Docker и Postgres не нужны):

```bash
cd backend && npm install && npm run seed && npm run dev
```

iOS: проект собирается в GitHub Actions на macOS. На Mac — `brew install xcodegen`, затем `cd ios && xcodegen generate` и открыть `iStore.xcodeproj`. Подробности — в README каждой папки.

## Установка на реальное устройство

iOS ставит приложения по OTA при HTTPS и действительной подписи IPA с подходящим provisioning profile. Ad Hoc требует зарегистрированного UDID, Enterprise допускает только внутреннее распространение.
