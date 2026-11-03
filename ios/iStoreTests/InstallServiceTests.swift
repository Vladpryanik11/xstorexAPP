import XCTest
@testable import iStore

/// Мок API: ответы задаются замыканием по методу и пути, вызовы записываются.
final class MockAPIClient: APIClientProtocol, @unchecked Sendable {
    typealias Handler = (_ method: HTTPMethod, _ path: String, _ callIndex: Int) throws -> String

    private let lock = NSLock()
    private var handler: Handler
    private var log: [(HTTPMethod, String)] = []

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var recordedCalls: [(HTTPMethod, String)] {
        lock.lock()
        defer { lock.unlock() }
        return log
    }

    func calls(method: HTTPMethod, path: String) -> Int {
        recordedCalls.filter { $0.0 == method && $0.1 == path }.count
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        lock.lock()
        let index = log.filter { $0.0 == endpoint.method && $0.1 == endpoint.path }.count
        log.append((endpoint.method, endpoint.path))
        let handler = self.handler
        lock.unlock()

        let json = try handler(endpoint.method, endpoint.path, index)
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }
        return try JSONCoding.makeDecoder().decode(Response.self, from: Data(json.utf8))
    }

    func makeRequest<Response>(for endpoint: Endpoint<Response>) async throws -> URLRequest {
        URLRequest(url: URL(string: "https://example.test/api/v1" + endpoint.path)!)
    }
}

@MainActor
final class MockOpener: URLOpening {
    var result = true
    /// Вызывается, пока ссылка «открывается».
    var onOpen: (() -> Void)?
    private(set) var opened: [URL] = []

    func open(_ url: URL) async -> Bool {
        opened.append(url)
        onOpen?()
        return result
    }
}

struct MockDevice: DeviceCapacityProviding {
    var osVersion: String = "17.0"
    var free: Int64? = 64 * 1024 * 1024 * 1024

    func freeDiskBytes() -> Int64? { free }
}

@MainActor
final class InstallServiceTests: XCTestCase {
    private var states: [InstallState] = []

    private func makeService(
        api: MockAPIClient,
        opener: MockOpener,
        device: MockDevice = MockDevice()
    ) -> InstallService {
        let service = InstallService(
            api: api,
            opener: opener,
            device: device,
            telemetry: nil,
            pollInterval: 0.01,
            maxPollAttempts: 5,
            installingResetDelay: 0.05
        )
        states = []
        service.addObserver(self) { [weak self] _, state in
            self?.states.append(state)
        }
        return service
    }

    private func makeApp(_ json: String = Fixtures.summary(id: "app_a")) throws -> AppSummary {
        try JSONCoding.makeDecoder().decode(AppSummary.self, from: Data(json.utf8))
    }

    /// Ждёт условия без `fulfillment(of:)`, которого нет в iOS 15.
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Состояния без повторов подряд.
    private var distinctStates: [InstallState] {
        var result: [InstallState] = []
        for state in states where result.last != state {
            result.append(state)
        }
        return result
    }

    func testHappyPathGoesThroughAllStages() async throws {
        let api = MockAPIClient { method, path, _ in
            switch (method, path) {
            case (.post, "/catalog/installs"):
                return Fixtures.grant(status: "preparing", itms: false)
            case (.get, "/catalog/installs/ins_1"):
                return Fixtures.grant(status: "ready")
            default:
                return "{}"
            }
        }
        let opener = MockOpener()
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()

        XCTAssertEqual(service.start(app), .started)
        XCTAssertEqual(service.start(app), .alreadyRunning)

        await waitUntil { self.states.last == .idle }

        XCTAssertEqual(distinctStates, [.preparing, .ready, .handingOff, .installing, .idle])
        XCTAssertEqual(opener.opened.first?.scheme, "itms-services")
        XCTAssertEqual(api.calls(method: .get, path: "/catalog/installs/ins_1"), 1)
        await waitUntil { api.calls(method: .post, path: "/catalog/installs/ins_1/events") >= 4 }
        XCTAssertEqual(api.calls(method: .post, path: "/catalog/installs/ins_1/events"), 4)
        XCTAssertEqual(service.state(for: app.id), .idle)
        XCTAssertTrue(service.activeInstalls.isEmpty)
    }

    func testServerFailureEndsInFailedWithCode() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                return Fixtures.grant(status: "failed", itms: false, errorCode: "signing_failed")
            }
            return "{}"
        }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp()
        service.start(app)

        await waitUntil { if case .failed? = self.states.last { return true } else { return false } }
        XCTAssertEqual(service.state(for: app.id), .failed(code: "signing_failed"))
        XCTAssertEqual(service.activeInstalls.count, 1, "Упавшая установка остаётся в Менеджере")

        service.dismiss(appId: app.id)
        XCTAssertEqual(service.state(for: app.id), .idle)
    }

    func testAPIErrorIsMappedToInstallCode() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                throw APIError.conflict(code: "no_build")
            }
            return "{}"
        }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp()
        service.start(app)

        await waitUntil { if case .failed? = self.states.last { return true } else { return false } }
        XCTAssertEqual(service.state(for: app.id), .failed(code: InstallErrorCode.noBuild))
    }

    func testOpenerFailure() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                return Fixtures.grant(status: "ready")
            }
            return "{}"
        }
        let opener = MockOpener()
        opener.result = false
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()
        service.start(app)

        await waitUntil { if case .failed? = self.states.last { return true } else { return false } }
        XCTAssertEqual(service.state(for: app.id), .failed(code: InstallErrorCode.launchFailed))
        XCTAssertEqual(distinctStates, [.preparing, .ready, .handingOff, .failed(code: InstallErrorCode.launchFailed)])
    }

    func testMissingItmsURLFails() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                return Fixtures.grant(status: "ready", itms: false)
            }
            return "{}"
        }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp()
        service.start(app)

        await waitUntil { if case .failed? = self.states.last { return true } else { return false } }
        XCTAssertEqual(service.state(for: app.id), .failed(code: InstallErrorCode.installURLMissing))
    }

    func testPollingTimesOut() async throws {
        let api = MockAPIClient { _, _, _ in
            Fixtures.grant(status: "preparing", itms: false)
        }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp()
        service.start(app)

        await waitUntil { if case .failed? = self.states.last { return true } else { return false } }
        XCTAssertEqual(service.state(for: app.id), .failed(code: InstallErrorCode.timedOut))
        XCTAssertEqual(api.calls(method: .get, path: "/catalog/installs/ins_1"), 5)
    }

    func testNotReadyKeepsPolling() async throws {
        let api = MockAPIClient { method, path, index in
            switch (method, path) {
            case (.post, "/catalog/installs"):
                return Fixtures.grant(status: "preparing", itms: false)
            case (.get, "/catalog/installs/ins_1"):
                if index == 0 {
                    throw APIError.conflict(code: "not_ready")
                }
                return Fixtures.grant(status: "ready")
            default:
                return "{}"
            }
        }
        let opener = MockOpener()
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()
        service.start(app)

        await waitUntil { self.states.last == .idle }
        XCTAssertEqual(opener.opened.count, 1)
        XCTAssertEqual(api.calls(method: .get, path: "/catalog/installs/ins_1"), 2)
    }

    func testExpiredGrantIsRequestedAgainOnce() async throws {
        let api = MockAPIClient { method, path, index in
            switch (method, path) {
            case (.post, "/catalog/installs"):
                return index == 0
                    ? Fixtures.grant(status: "preparing", itms: false)
                    : Fixtures.grant(status: "ready", id: "ins_2")
            case (.get, "/catalog/installs/ins_1"):
                throw APIError.grantExpired
            default:
                return "{}"
            }
        }
        let opener = MockOpener()
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()
        service.start(app)

        await waitUntil { self.states.last == .idle }
        XCTAssertEqual(api.calls(method: .post, path: "/catalog/installs"), 2)
        XCTAssertEqual(opener.opened.count, 1)
    }

    func testGrantExpiredWhilePreparingIsRequestedAgain() async throws {
        let api = MockAPIClient { method, path, index in
            switch (method, path) {
            case (.post, "/catalog/installs"):
                return index == 0
                    ? Fixtures.grant(status: "preparing", itms: false)
                    : Fixtures.grant(status: "ready", id: "ins_2")
            case (.get, "/catalog/installs/ins_1"):
                // Так сервер отвечает на опрос истёкшего гранта: 200, `failed` и `grant_expired`.
                return Fixtures.grant(status: "failed", itms: false, errorCode: "grant_expired")
            default:
                return "{}"
            }
        }
        let opener = MockOpener()
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()
        service.start(app)

        await waitUntil { self.states.last == .idle }
        XCTAssertEqual(api.calls(method: .post, path: "/catalog/installs"), 2)
        XCTAssertEqual(opener.opened.count, 1)
        XCTAssertFalse(states.contains { if case .failed = $0 { return true } else { return false } })
    }

    func testCancelWhileHandingOffStaysCancelled() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                return Fixtures.grant(status: "ready")
            }
            return "{}"
        }
        let opener = MockOpener()
        let service = makeService(api: api, opener: opener)
        let app = try makeApp()
        opener.onOpen = { [weak service] in
            service?.cancel(appId: app.id)
        }
        service.start(app)

        await waitUntil { opener.opened.count == 1 }
        // Время, за которое задача дошла бы до `.installing`.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(service.state(for: app.id), .idle)
        XCTAssertTrue(service.activeInstalls.isEmpty)
        XCTAssertFalse(states.contains(.installing))
    }

    func testIncompatibleOSIsBlockedBeforeStart() throws {
        let api = MockAPIClient { _, _, _ in "{}" }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp(Fixtures.summary(id: "app_new", minOS: "99.0"))

        XCTAssertEqual(service.preflight(for: app), .incompatible(requiredOS: "99.0"))
        XCTAssertEqual(service.start(app), .blocked(.incompatible(requiredOS: "99.0")))
        XCTAssertEqual(service.state(for: app.id), .idle)
        XCTAssertTrue(api.recordedCalls.isEmpty)
    }

    func testLowSpaceNeedsConfirmation() async throws {
        let api = MockAPIClient { method, path, _ in
            if method == .post && path == "/catalog/installs" {
                return Fixtures.grant(status: "ready")
            }
            return "{}"
        }
        let device = MockDevice(osVersion: "17.0", free: 10 * 1024 * 1024)
        let service = makeService(api: api, opener: MockOpener(), device: device)
        let app = try makeApp(Fixtures.summary(id: "app_big", size: 500 * 1024 * 1024))

        guard case .blocked(.lowSpace) = service.start(app) else {
            return XCTFail("Ожидалась блокировка из-за места")
        }
        XCTAssertTrue(api.recordedCalls.isEmpty)

        XCTAssertEqual(service.start(app, allowLowSpace: true), .started)
        await waitUntil { self.states.last == .idle }
        XCTAssertEqual(api.calls(method: .post, path: "/catalog/installs"), 1)
    }

    func testUnavailableAppIsBlocked() throws {
        let service = makeService(api: MockAPIClient { _, _, _ in "{}" }, opener: MockOpener())
        let app = try makeApp(Fixtures.summary(id: "app_gone", availability: "unavailable"))
        XCTAssertEqual(service.start(app), .blocked(.unavailable))
    }

    func testCancelReturnsToIdle() async throws {
        let api = MockAPIClient { _, _, _ in
            Fixtures.grant(status: "preparing", itms: false)
        }
        let service = makeService(api: api, opener: MockOpener())
        let app = try makeApp()
        service.start(app)
        XCTAssertEqual(service.state(for: app.id), .preparing)
        service.cancel(appId: app.id)
        XCTAssertEqual(service.state(for: app.id), .idle)
        XCTAssertTrue(service.activeInstalls.isEmpty)
    }
}
