import Foundation

/// Живое изменение каталога для экранов.
enum CatalogLiveEvent: Sendable, Equatable {
    /// Приложение добавлено или изменилось.
    case appUpserted(AppSummary)
    /// Приложение снято с публикации: его нужно сразу скрыть.
    case appRemoved(String)
    /// Изменился состав комнат: витрину стоит перечитать.
    case roomsChanged
    /// Журнал обрезан: витрину нужно перечитать целиком.
    case reset
}

protocol CatalogLiveObserving: Sendable {
    func subscribe() async -> AsyncStream<CatalogLiveEvent>
    func noteRevision(_ revision: Int) async
}

/// SSE `/catalog/stream` с переподключением и догоном через `/catalog/changes`.
actor CatalogLiveSync: CatalogLiveObserving {
    private enum StreamOutcome {
        case ended(receivedEvents: Bool)
        case failed
        case unauthorized
    }

    private let api: APIClientProtocol
    private let catalog: CatalogServicing
    private let session: URLSession
    private let decoder = JSONCoding.makeDecoder()

    private var streamTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<CatalogLiveEvent>.Continuation] = [:]
    /// Единственный курсор потока: уходит в `?since=` и двигается и по SSE, и по догону, и по `/groupings`.
    private(set) var lastRevision: Int?
    private(set) var isConnected = false

    init(api: APIClientProtocol, catalog: CatalogServicing, session: URLSession = CatalogLiveSync.makeSession()) {
        self.api = api
        self.catalog = catalog
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Сервер шлёт `: ping` каждые 25 секунд, поэтому 60 секунд тишины — разрыв.
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    // MARK: - Подписка

    func subscribe() -> AsyncStream<CatalogLiveEvent> {
        let id = UUID()
        var captured: AsyncStream<CatalogLiveEvent>.Continuation?
        let stream = AsyncStream<CatalogLiveEvent>(bufferingPolicy: .bufferingNewest(64)) { continuation in
            captured = continuation
        }
        if let continuation = captured {
            subscribers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                Task { await self.removeSubscriber(id) }
            }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast(_ event: CatalogLiveEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)
        }
    }

    // MARK: - Жизненный цикл

    /// Ревизия из ответа `/groupings`: с неё начинается поток.
    func noteRevision(_ revision: Int) {
        advance(to: revision)
    }

    func start() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    /// Полный сброс при выходе из аккаунта.
    func reset() {
        stop()
        lastRevision = nil
    }

    static func backoffDelay(attempt: Int) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        let base = min(60.0, pow(2.0, exponent))
        return base + Double.random(in: 0...0.3) * base
    }

    private func runLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let outcome = await connectOnce()
            if Task.isCancelled { break }
            switch outcome {
            case .unauthorized:
                streamTask = nil
                return
            case .ended(let receivedEvents):
                if receivedEvents { attempt = 0 }
            case .failed:
                break
            }
            await catchUp()
            attempt += 1
            let delay = Self.backoffDelay(attempt: attempt)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }

    private func connectOnce() async -> StreamOutcome {
        var query: [QueryParam] = []
        if let revision = lastRevision {
            query.append(QueryParam("since", String(revision)))
        }
        let endpoint = Endpoint<EmptyResponse>(path: "/catalog/stream", query: query, timeout: 60)
        guard var request = try? await api.makeRequest(for: endpoint) else {
            return .failed
        }
        guard request.value(forHTTPHeaderField: "Authorization") != nil else {
            return .unauthorized
        }
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // `Last-Event-ID` не шлём: сервер предпочёл бы его `since`, а id двигается только по событиям SSE
        // и отстаёт после догона через `/catalog/changes`.

        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed
            }
            if http.statusCode == 401 {
                return .unauthorized
            }
            guard http.statusCode == 200 else {
                return .failed
            }
            isConnected = true
            var splitter = SSELineSplitter()
            var parser = SSEParser()
            var received = false
            for try await byte in bytes {
                guard let line = splitter.append(byte) else { continue }
                if let event = parser.consume(line: line) {
                    received = true
                    handle(event)
                }
            }
            if let line = splitter.finish(), let event = parser.consume(line: line) {
                handle(event)
            }
            if let event = parser.finish() {
                handle(event)
            }
            isConnected = false
            return .ended(receivedEvents: received)
        } catch {
            isConnected = false
            return .failed
        }
    }

    // MARK: - События

    /// Курсор двигают только `change` и `reset`: у `hello` в `id` лежит присланный `since`, а не текущая ревизия.
    private func handle(_ event: SSEEvent) {
        let data = Data(event.data.utf8)
        switch event.event {
        case "hello":
            break
        case "change":
            if let change = try? decoder.decode(CatalogChange.self, from: data) {
                apply(change)
            }
        case "reset":
            if let payload = try? decoder.decode(RevisionPayload.self, from: data) {
                lastRevision = payload.revision
            }
            broadcast(.reset)
        default:
            break
        }
    }

    private func apply(_ change: CatalogChange) {
        advance(to: change.revision)
        switch change.kind {
        case .appUpsert:
            if let app = change.app {
                broadcast(app.isAvailable ? .appUpserted(app) : .appRemoved(app.id))
            }
        case .appRemoved:
            if let id = change.appId ?? change.app?.id {
                broadcast(.appRemoved(id))
            }
        case .roomsChanged:
            broadcast(.roomsChanged)
        case .unknown:
            break
        }
    }

    private func advance(to revision: Int) {
        if let current = lastRevision, current >= revision {
            return
        }
        lastRevision = revision
    }

    /// Догон пропущенного после разрыва: `/catalog/changes?since=` постранично.
    func catchUp() async {
        guard var cursor = lastRevision else { return }
        for _ in 0..<10 {
            guard let response = try? await catalog.changes(since: cursor) else { return }
            if response.reset {
                lastRevision = response.revision
                broadcast(.reset)
                return
            }
            for change in response.changes {
                apply(change)
            }
            cursor = response.changes.last?.revision ?? response.revision
            if !response.hasMore {
                advance(to: response.revision)
                return
            }
        }
    }
}
