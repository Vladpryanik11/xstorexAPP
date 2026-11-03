# iStore

Магазин iOS-приложений по подписке: витрина в стиле App Store, установка по воздуху (OTA), аккаунт по коду активации. В каталоге только собственные и лицензированные приложения.

| Папка | Что внутри |
|---|---|
| [docs/SPEC.md](docs/SPEC.md) | ТЗ: решения, этапы, визуальный стиль, архитектура |
| [docs/API.md](docs/API.md) | Контракт API v1, общий для бэкенда и клиента |
| [backend/](backend/) | Node.js 22 + TypeScript, Fastify, Drizzle, PostgreSQL / PGlite |
| [ios/](ios/) | Swift, UIKit, iOS 15+, проект генерирует XcodeGen |
| [.github/workflows/](.github/workflows/) | CI: тесты бэкенда (Ubuntu), сборка и тесты iOS (macOS) |

## Быстрый старт

Бэкенд (Windows, macOS, Linux; Docker и Postgres не нужны):

```bash
cd backend && npm install && npm run seed && npm run dev
```

iOS: проект собирается в GitHub Actions на macOS. На Mac — `brew install xcodegen`, затем `cd ios && xcodegen generate` и открыть `iStore.xcodeproj`. Подробности — в README каждой папки.

## Установка на реальное устройство

iOS ставит приложения по OTA, только если манифест и IPA отдаются по HTTPS с валидным сертификатом, а IPA подписан сертификатом владельца магазина: ad hoc с зарегистрированными устройствами или Enterprise для внутренних сотрудников.
