import XCTest
@testable import iStore

@MainActor
final class PushCoordinatorTests: XCTestCase {
    private func makeCoordinator(api: MockAPIClient, token: String?) -> PushCoordinator {
        PushCoordinator(
            api: api,
            tokenStore: InMemoryTokenStore(token: token),
            environment: "sandbox",
            registerForRemote: {}
        )
    }

    func testHexToken() {
        XCTAssertEqual(PushCoordinator.hexString(from: Data([0x00, 0x0f, 0xa0, 0xff])), "000fa0ff")
    }

    func testAppIdFromPayload() {
        XCTAssertEqual(PushCoordinator.appId(from: ["kind": "app_update", "app_id": "app_a"]), "app_a")
        XCTAssertNil(PushCoordinator.appId(from: ["kind": "test"]))
        XCTAssertNil(PushCoordinator.appId(from: ["app_id": ""]))
        XCTAssertNil(PushCoordinator.appId(from: ["app_id": 42]))
        XCTAssertNil(PushCoordinator.appId(from: ["app_id": String(repeating: "a", count: 81)]))
    }

    func testTokenBodyUsesSnakeCase() throws {
        let body = PushTokenBody(apnsToken: "ab", apnsEnv: "production", locale: "ru", tzOffsetMinutes: 180)
        let data = try JSONCoding.makeEncoder().encode(body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["apns_token"] as? String, "ab")
        XCTAssertEqual(object["apns_env"] as? String, "production")
        XCTAssertEqual(object["locale"] as? String, "ru")
        XCTAssertEqual(object["tz_offset_minutes"] as? Int, 180)
    }

    func testUploadsTokenOnlyWhenSignedIn() async {
        let api = MockAPIClient { _, _, _ in "" }
        await makeCoordinator(api: api, token: nil).didRegister(deviceToken: Data([0x01]))
        XCTAssertTrue(api.recordedCalls.isEmpty, "Без входа токен на сервер не уходит")

        await makeCoordinator(api: api, token: "tok").didRegister(deviceToken: Data([0x01]))
        XCTAssertEqual(api.calls(method: .post, path: "/client/push-token"), 1)
    }

    func testTapBeforeRouterIsReadyIsDeliveredLater() {
        let coordinator = makeCoordinator(api: MockAPIClient { _, _, _ in "" }, token: "tok")
        coordinator.open(appId: "app_a")
        var opened: [String] = []
        coordinator.onOpenApp = { opened.append($0) }
        coordinator.open(appId: "app_b")
        XCTAssertEqual(opened, ["app_a", "app_b"])
    }

    func testDebugBuildUsesSandbox() {
        XCTAssertEqual(AppConfiguration.load().apnsEnvironment, "sandbox")
    }
}
