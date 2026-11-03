import XCTest
@testable import iStore

final class CatalogLiveSyncTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.store.reset()
    }

    override func tearDown() {
        MockURLProtocol.store.reset()
        super.tearDown()
    }

    /// После догона через `/catalog/changes` поток переподключается с новым `since`
    /// и без `Last-Event-ID`: иначе сервер взял бы отставший id и прислал старые изменения или `reset`.
    func testReconnectUsesRevisionFromCatchUp() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let identity = ClientIdentity(
            baseURL: URL(string: "http://localhost:8080")!,
            language: "ru",
            build: "42",
            installId: "install-uuid"
        )
        let api = APIClient(identity: identity, tokenStore: InMemoryTokenStore(token: "tok_live"), session: session)
        let live = CatalogLiveSync(api: api, catalog: CatalogService(api: api), session: session)

        let sse = """
        id: 120
        event: hello
        data: {"revision":120}

        id: 121
        event: change
        data: {"revision":121,"kind":"rooms_changed","app_id":null,"app":null}


        """
        MockURLProtocol.store.enqueue(.init(status: 200, headers: ["Content-Type": "text/event-stream"], body: sse))
        MockURLProtocol.store.enqueue(.init(
            status: 200,
            body: #"{"revision":500,"changes":[],"has_more":false,"reset":false}"#
        ))
        MockURLProtocol.store.enqueue(.init(
            status: 401,
            body: #"{"error":{"code":"unauthorized","message":"Нужен вход"}}"#
        ))

        await live.noteRevision(120)
        await live.start()

        let deadline = Date().addingTimeInterval(5)
        while MockURLProtocol.store.recorded.count < 3, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        await live.stop()

        let requests = MockURLProtocol.store.recorded
        XCTAssertEqual(requests.count, 3)
        guard requests.count == 3 else { return }
        XCTAssertEqual(requests[0].url?.path, "/api/v1/catalog/stream")
        XCTAssertEqual(query(requests[0], "since"), "120")
        XCTAssertEqual(requests[1].url?.path, "/api/v1/catalog/changes")
        XCTAssertEqual(query(requests[1], "since"), "121")
        XCTAssertEqual(requests[2].url?.path, "/api/v1/catalog/stream")
        XCTAssertEqual(query(requests[2], "since"), "500")
        XCTAssertNil(requests[2].value(forHTTPHeaderField: "Last-Event-ID"))
        let revision = await live.lastRevision
        XCTAssertEqual(revision, 500)
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?.first { $0.name == name }?.value
    }
}
