import XCTest
@testable import iStore

/// Подменяет сеть: отдаёт заранее заданные ответы и запоминает запросы.
final class MockURLProtocol: URLProtocol {
    struct Stub {
        var status: Int
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: String = ""
    }

    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var stubs: [Stub] = []
        private var requests: [URLRequest] = []

        func enqueue(_ stub: Stub) {
            lock.lock()
            stubs.append(stub)
            lock.unlock()
        }

        func next(for request: URLRequest) -> Stub? {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return stubs.isEmpty ? nil : stubs.removeFirst()
        }

        var recorded: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return requests
        }

        func reset() {
            lock.lock()
            stubs = []
            requests = []
            lock.unlock()
        }
    }

    static let store = Store()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = MockURLProtocol.store.next(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Первый `token()` отдаёт старый токен (он уходит в запрос), дальше хранится уже новый:
/// так выглядит повторная активация, случившаяся, пока запрос был в пути.
actor ReplacingTokenStore: TokenStoring {
    private let sent: String
    private var value: String?
    private var didSend = false

    init(sent: String, replacement: String) {
        self.sent = sent
        self.value = replacement
    }

    func token() -> String? {
        if !didSend {
            didSend = true
            return sent
        }
        return value
    }

    func save(_ token: String) { value = token }
    func clear() { value = nil }

    func clear(ifEqualTo token: String) -> Bool {
        guard let current = value else { return true }
        guard current == token else { return false }
        value = nil
        return true
    }
}

/// Флаг, который можно выставить из `@Sendable`-колбэка.
actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class APIClientTests: XCTestCase {
    private var tokenStore: InMemoryTokenStore!
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        MockURLProtocol.store.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        tokenStore = InMemoryTokenStore(token: "tok_live")
        let identity = ClientIdentity(
            baseURL: URL(string: "http://localhost:8080")!,
            language: "ru",
            build: "42",
            installId: "install-uuid"
        )
        client = APIClient(identity: identity, tokenStore: tokenStore, session: session)
    }

    override func tearDown() {
        MockURLProtocol.store.reset()
        client = nil
        tokenStore = nil
        super.tearDown()
    }

    func testHeadersAndPath() async throws {
        MockURLProtocol.store.enqueue(.init(status: 200, body: Fixtures.storeOpen))
        _ = try await client.send(Endpoint<StoreState>(path: "/client/store-state", requiresAuth: false))
        MockURLProtocol.store.enqueue(.init(status: 200, body: Fixtures.search))
        _ = try await client.send(Endpoint<SearchResponse>(path: "/search", query: [QueryParam("q", "c++ notes")]))

        let requests = MockURLProtocol.store.recorded
        XCTAssertEqual(requests.count, 2)
        let first = requests[0]
        XCTAssertEqual(first.url?.path, "/api/v1/client/store-state")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Accept-Language"), "ru")
        XCTAssertEqual(first.value(forHTTPHeaderField: "X-Client-Build"), "42")
        XCTAssertEqual(first.value(forHTTPHeaderField: "X-Install-Id"), "install-uuid")
        XCTAssertNil(first.value(forHTTPHeaderField: "Authorization"), "Публичный маршрут без токена")

        let second = requests[1]
        XCTAssertEqual(second.value(forHTTPHeaderField: "Authorization"), "Bearer tok_live")
        let absolute = second.url?.absoluteString ?? ""
        XCTAssertTrue(absolute.hasSuffix("/api/v1/search?q=c%2B%2B%20notes"), absolute)
    }

    func test401ClearsTokenAndNotifies() async {
        let counter = CallCounter()
        await client.setUnauthorizedHandler {
            await counter.increment()
        }
        MockURLProtocol.store.enqueue(.init(
            status: 401,
            body: #"{"error":{"code":"unauthorized","message":"Нужен вход"}}"#
        ))
        do {
            _ = try await client.send(Endpoint<ClientProfile>(path: "/client/profile"))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        let token = await tokenStore.token()
        XCTAssertNil(token)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    func test401ForReplacedTokenKeepsNewToken() async {
        let store = ReplacingTokenStore(sent: "tok_old", replacement: "tok_new")
        let identity = ClientIdentity(
            baseURL: URL(string: "http://localhost:8080")!,
            language: "ru",
            build: "42",
            installId: "install-uuid"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let replacingClient = APIClient(identity: identity, tokenStore: store, session: URLSession(configuration: configuration))
        let counter = CallCounter()
        await replacingClient.setUnauthorizedHandler {
            await counter.increment()
        }
        MockURLProtocol.store.enqueue(.init(
            status: 401,
            body: #"{"error":{"code":"unauthorized","message":"Нужен вход"}}"#
        ))
        do {
            _ = try await replacingClient.send(Endpoint<ClientProfile>(path: "/client/profile"))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        XCTAssertEqual(MockURLProtocol.store.recorded.first?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_old")
        let token = await store.token()
        XCTAssertEqual(token, "tok_new", "Ответ на старый токен не стирает выданный после него")
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func test401GrantExpiredKeepsToken() async {
        MockURLProtocol.store.enqueue(.init(
            status: 401,
            body: #"{"error":{"code":"grant_expired","message":"Грант истёк"}}"#
        ))
        do {
            _ = try await client.send(Endpoint<InstallGrant>(path: "/catalog/installs/ins_1"))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .grantExpired)
        }
        let token = await tokenStore.token()
        XCTAssertEqual(token, "tok_live")
    }

    func test404WithCode() async {
        MockURLProtocol.store.enqueue(.init(status: 404, body: Fixtures.error))
        do {
            _ = try await client.send(Endpoint<ActivateResponse>(path: "/app/activate", method: .post, requiresAuth: false))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound(code: "invalid_code"))
        }
    }

    func test403AccountInactiveNotifies() async {
        let counter = CallCounter()
        await client.setAccountInactiveHandler {
            await counter.increment()
        }
        MockURLProtocol.store.enqueue(.init(
            status: 403,
            body: #"{"error":{"code":"account_inactive","message":"Подписка закончилась"}}"#
        ))
        do {
            _ = try await client.send(Endpoint<GroupingsResponse>(path: "/groupings", query: [QueryParam("tab", "today")]))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .accountInactive)
        }
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
        let token = await tokenStore.token()
        XCTAssertEqual(token, "tok_live", "403 не разлогинивает")
    }

    func test409And429() async {
        MockURLProtocol.store.enqueue(.init(status: 409, body: #"{"error":{"code":"code_used","message":"x"}}"#))
        MockURLProtocol.store.enqueue(.init(
            status: 429,
            headers: ["Content-Type": "application/json", "Retry-After": "30"],
            body: #"{"error":{"code":"rate_limited","message":"x"}}"#
        ))
        do {
            _ = try await client.send(Endpoint<EmptyResponse>(path: "/app/activate", method: .post, requiresAuth: false))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .conflict(code: "code_used"))
        }
        do {
            _ = try await client.send(Endpoint<EmptyResponse>(path: "/app/activate", method: .post, requiresAuth: false))
            XCTFail("Ожидалась ошибка")
        } catch {
            XCTAssertEqual(error as? APIError, .rateLimited(retryAfter: 30))
        }
    }

    func test304ReturnsCachedBodyAndSendsIfNoneMatch() async throws {
        MockURLProtocol.store.enqueue(.init(
            status: 200,
            headers: ["Content-Type": "application/json", "ETag": "\"rev-42\""],
            body: Fixtures.groupings
        ))
        MockURLProtocol.store.enqueue(.init(status: 304, headers: ["ETag": "\"rev-42\""], body: ""))

        let endpoint = Endpoint<GroupingsResponse>(path: "/groupings", query: [QueryParam("tab", "today")], usesETag: true)
        let first = try await client.send(endpoint)
        let second = try await client.send(endpoint)

        XCTAssertEqual(first.revision, 42)
        XCTAssertEqual(second.revision, 42)
        XCTAssertEqual(second.rooms.count, first.rooms.count)

        let requests = MockURLProtocol.store.recorded
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "If-None-Match"), "\"rev-42\"")
    }

    func testEmptyBodyFor204() async throws {
        MockURLProtocol.store.enqueue(.init(status: 204, body: ""))
        let result = try await client.send(Endpoint<EmptyResponse>(path: "/app/sign-out", method: .post))
        XCTAssertEqual(result, EmptyResponse())
    }

    func testOfflineMapsToOffline() {
        XCTAssertEqual(APIError.from(transportError: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(APIError.from(transportError: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(APIError.from(transportError: CancellationError()), .cancelled)
    }

    func testStatusMapping() {
        XCTAssertEqual(APIError.from(status: 500, body: nil, retryAfterHeader: nil), .server(status: 500, code: nil))
        XCTAssertEqual(
            APIError.from(status: 409, body: #"{"error":{"code":"not_ready","message":""}}"#.data, retryAfterHeader: nil),
            .conflict(code: "not_ready")
        )
        XCTAssertEqual(
            APIError.from(status: 400, body: #"{"error":{"code":"invalid_request","message":"bad"}}"#.data, retryAfterHeader: nil),
            .invalidRequest(code: "invalid_request", message: "bad")
        )
    }
}
