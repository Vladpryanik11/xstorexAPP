# iStore — iOS-клиент (этап 1)

Программный UIKit, Swift 5 language mode со строгой проверкой конкурентности `targeted`, iOS 15.0+, iPhone и iPad. Без сторонних зависимостей. Проект генерирует [XcodeGen](https://github.com/yonaskolb/XcodeGen) из `project.yml`, сам `iStore.xcodeproj` в репозиторий не кладётся.

## Генерация и сборка

```bash
brew install xcodegen
cd ios
xcodegen generate
open iStore.xcodeproj
```

Тесты из терминала (подставьте любой доступный симулятор iPhone):

```bash
xcodebuild test -project iStore.xcodeproj -scheme iStore \
  -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO
```

В CI то же самое делает [`.github/workflows/ios.yml`](../.github/workflows/ios.yml) на `macos-latest`: генерирует проект, сам выбирает симулятор и запускает тесты. Workflow стартует на push и PR с изменениями в `ios/**` и вручную (`workflow_dispatch`).

## Запуск с локальным бэкендом

Адрес API берётся из `Info.plist` (`IStoreAPIBaseURL = $(ISTORE_API_BASE_URL)`):

| Конфигурация | `ISTORE_API_BASE_URL` |
|---|---|
| Debug | `http://localhost:8080` |
| Release | `https://api.istore.example` |

1. Поднимите бэкенд: `cd backend && npm install && npm run seed && npm run dev` (слушает `http://localhost:8080`).
2. Запустите схему `iStore` на симуляторе: симулятор видит `localhost` машины.
3. На экране входа введите dev-код **`DEMO-DEMO-0001`**.

Другой адрес:
- в Debug — переменная окружения `ISTORE_API_BASE_URL` в схеме (Edit Scheme → Run → Environment Variables), она важнее значения из `Info.plist`;
- при сборке — `xcodebuild … ISTORE_API_BASE_URL=http://192.168.1.20:8080`.

ATS включён, разрешена только локальная сеть (`NSAllowsLocalNetworking`). Всё остальное — только HTTPS.

## Структура

```
ios/
  project.yml                 XcodeGen: таргеты iStore и iStoreTests, Info.plist, схема
  scripts/make-icon.mjs       генератор AppIcon 1024×1024 (свой PNG-энкодер на zlib)
  scripts/check-l10n.mjs      проверка ключей en/ru и ключей из кода
  iStore/
    App/                      AppDelegate, SceneDelegate, AppConfiguration, AppContainer (composition root),
                              FeatureFactory, AppFlowController (роутер и окна-шлюзы), MainTabBarController
    Core/
      Networking/             Endpoint, APIClient (actor), APIError
      Auth/                   KeychainStore, TokenStore, InstallID, ActivationCode, DeviceInfo, AuthService
      Client/                 модели Account/StoreState/ClientVersion, ClientService (профиль, состояние магазина)
      Catalog/                модели каталога, CatalogService, SSEParser, CatalogLiveSync
      Install/                InstallGrant, InstallState, InstallService (машина состояний)
      Telemetry/              TelemetryRecorder (actor, батчи)
      ClientUpdate/           ClientUpdateService
    Features/
      Activation/             вход по коду
      Gates/                  заглушка старта, «Магазин закрыт», «Подписка закончилась»
      Storefront/             витрина (Сегодня/Игры/Приложения), ячейки, layout, «Показать все»
      AppDetail/              карточка приложения, история версий
      Search/                 поиск и история
      Manager/                активные установки
      Account/                шит аккаунта
      ClientUpdate/           обновление клиента
    Shared/
      DesignSystem/           палитра, градиенты, стекло, InstallButton, AppIconView, ImagePipeline, баннер
      Components/             AppRowCell, InstallPrompter
      L10n.swift, Routing.swift, Formatters.swift, ErrorPresentation.swift
    Resources/                Assets.xcassets (AppIcon, AccentColor), en.lproj, ru.lproj
  iStoreTests/                декодирование схем API, APIClient на моке URLProtocol,
                              код активации, машина состояний установки, SSE-парсер
```

Правила слоёв: `Features` зависят от `Core` и `Shared`, но не друг от друга. Переходы между экранами идут через протокол `AppRouting`, его реализует `AppFlowController`. Сеть и I/O — `actor`, UI — `@MainActor`, живые изменения каталога — `AsyncStream`.

## Что работает на этапе 1

- Вход по коду активации (`POST /app/activate`), токен и `X-Install-Id` в Keychain, выход с подтверждением.
- Окна-шлюзы поверх интерфейса: «Магазин закрыт» (обратный отсчёт, ссылки, автоопрос), вход, «Подписка закончилась» («Продлить» в Safari View Controller, «Я продлил»). Перепроверка при возврате в приложение. `401` разлогинивает, `403 account_inactive` открывает окно продления.
- Пять вкладок. Витрина на `UICollectionViewCompositionalLayout` + Diffable: hero-карусель, полки двух стилей, чипы, «Показать все» с пагинацией, pull-to-refresh, скелетон, ошибки и пустота. ETag-кэш в памяти.
- Живой каталог: SSE `/catalog/stream` с переподключением (backoff, `Last-Event-ID`), догон через `/catalog/changes`, снятые приложения исчезают сразу.
- Карточка приложения в цветах приложения: статистика, совместимость, скриншоты, описание, «Что нового», информация, история версий, похожие.
- Установка: проверка `min_os` и места, грант, опрос до `ready`, `itms-services://`, события стадий, кнопка с кольцом прогресса, баннер над таб-баром, Менеджер со списком установок.
- Поиск: подсказки с задержкой 250 мс, история, пагинация, «Показаны результаты для…», «Запросить приложение».
- Обновление клиента: шит или неснимаемое окно при `mandatory`.
- Телеметрия: `app.launch`, `install.step`, `net.error` пачками раз в 30 секунд и при уходе в фон.
- RU и EN, Dynamic Type, VoiceOver, тёмная тема, хаптики. Стекло iOS 26 (`UIGlassEffect`) при сборке Xcode 26, иначе `systemUltraThinMaterial`.

## Что требует HTTPS

Реальная OTA-установка. iOS открывает `itms-services://` только если манифест и IPA отдаются по HTTPS с валидным сертификатом, а IPA подписан сертификатом владельца магазина (ad hoc с зарегистрированными устройствами или Enterprise). С `http://localhost` клиент пройдёт все стадии до передачи в iOS, но система откажется ставить приложение. Для проверки на устройстве нужен бэкенд с `PUBLIC_BASE_URL` на HTTPS-домене (например, через туннель с валидным сертификатом).

## Иконка и локализация

```bash
node scripts/make-icon.mjs     # пересобрать AppIcon.png
node scripts/check-l10n.mjs    # en/ru: одинаковые ключи и спецификаторы, все ключи из кода на месте
```
