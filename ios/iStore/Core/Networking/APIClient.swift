import Foundation

/// Данные клиента, которые уходят в заголовках каждого запроса.
struct ClientIdentity: Sendable {
    /// Корень сервера, например `http://localhost:8080`.
    let baseURL: URL
    /// `ru` или `en`.
    let language: String
    /// `CFBundleVersion`.
    let build: String
    /// UUID установки из Keychain.
    let installId: String

    var apiBaseURL: URL {
        baseURL.appendingPathComponent("api/v1")
    }
}

/// Граница сети. Фичи и сервисы зависят от протокола, тесты подменяют его моком.
protocol APIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response
    /// Готовый запрос со всеми заголовками (нужен SSE-клиенту).
    func makeRequest<Response>(for endpoint: Endpoint<Response>) async throws -> URLRequest
}

/// HTTP-клиент API v1: заголовки, Bearer, маппинг ошибок, ETag-кэш в памяти.
actor APIClient: APIClientProtocol {
    typealias UnauthorizedHandler = @Sendable () async -> Void
    typealias AccountInactiveHandler = @Sendable () async -> Void
    typealias ErrorObserver = @Sendable (_ path: String, _ error: APIError) -> Void

    private struct CachedResponse {
        let etag: String
        let data: Data
    }

    private let identity: ClientIdentity
    private let session: URLSession
    private let tokenStore: TokenStoring
    private let decoder: JSONDecoder
    private var etagCache: [String: CachedResponse] = [:]
    private var unauthorizedHandler: UnauthorizedHandler?
    private var accountInactiveHandler: AccountInactiveHandler?
    private var errorObserver: ErrorObserver?

    init(identity: ClientIdentity, tokenStore: TokenStoring, session: URLSession = APIClient.makeSession()) {
        self.identity = identity
        self.tokenStore = tokenStore
        self.session = session
        self.decoder = JSONCoding.makeDecoder()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Настройка

    /// Колбэк на `401`: токен уже очищен, нужно показать окно входа.
    func setUnauthorizedHandler(_ handler: UnauthorizedHandler?) {
        unauthorizedHandler = handler
    }

    /// Колбэк на `403 account_inactive` у защищённых маршрутов: подписка закончилась,
    /// нужно показать окно продления (каталог, поиск и установки в этом состоянии закрыты).
    func setAccountInactiveHandler(_ handler: AccountInactiveHandler?) {
        accountInactiveHandler = handler
    }

    /// Наблюдатель сетевых ошибок (телеметрия `net.error`).
    func setErrorObserver(_ observer: ErrorObserver?) {
        errorObserver = observer
    }

    func clearCache() {
        etagCache.removeAll()
    }

    // MARK: - APIClientProtocol

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        var request = try await makeRequest(for: endpoint)
        let cacheKey = request.url?.absoluteString ?? endpoint.path
        let canUseETag = endpoint.usesETag && endpoint.method == .get
        if canUseETag, let cached = etagCache[cacheKey] {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }
        let sentToken = request.value(forHTTPHeaderField: "Authorization") != nil

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            let apiError = APIError.from(transportError: error)
            report(path: endpoint.path, error: apiError)
            throw apiError
        }
        let (data, response) = result

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(status: 0)
        }
        let status = http.statusCode

        if status == 304, canUseETag, let cached = etagCache[cacheKey] {
            return try decode(Response.self, from: cached.data)
        }

        if (200..<300).contains(status) {
            if canUseETag, let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
                etagCache[cacheKey] = CachedResponse(etag: etag, data: data)
            }
            return try decode(Response.self, from: data)
        }

        let error = APIError.from(
            status: status,
            body: data,
            retryAfterHeader: http.value(forHTTPHeaderField: "Retry-After")
        )
        if error == .unauthorized, endpoint.requiresAuth, sentToken {
            etagCache.removeAll()
            await tokenStore.clear()
            if let handler = unauthorizedHandler {
                await handler()
            }
        }
        if error == .accountInactive, endpoint.requiresAuth, sentToken, let handler = accountInactiveHandler {
            await handler()
        }
        report(path: endpoint.path, error: error)
        throw error
    }

    func makeRequest<Response>(for endpoint: Endpoint<Response>) async throws -> URLRequest {
        guard var components = URLComponents(url: identity.apiBaseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidRequest(code: "invalid_url", message: nil)
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let extraPath = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components.path = basePath + extraPath
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query.map { URLQueryItem(name: $0.name, value: $0.value) }
            // `+` в значении сервер прочитал бы как пробел.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else {
            throw APIError.invalidRequest(code: "invalid_url", message: nil)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(identity.language, forHTTPHeaderField: "Accept-Language")
        request.setValue(identity.build, forHTTPHeaderField: "X-Client-Build")
        request.setValue(identity.installId, forHTTPHeaderField: "X-Install-Id")
        if let timeout = endpoint.timeout {
            request.timeoutInterval = timeout
        }
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if endpoint.requiresAuth, let token = await tokenStore.token() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Private

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func report(path: String, error: APIError) {
        guard error != .cancelled, !path.hasPrefix("/client/events") else { return }
        errorObserver?(path, error)
    }
}
