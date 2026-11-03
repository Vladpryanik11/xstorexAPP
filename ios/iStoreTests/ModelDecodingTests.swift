import XCTest
@testable import iStore

final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONCoding.makeDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: json.data)
    }

    func testAppSummary() throws {
        let app = try decode(AppSummary.self, Fixtures.appSummary)
        XCTAssertEqual(app.id, "app_7f3k2")
        XCTAssertEqual(app.iconUrl?.absoluteString, "https://cdn.istore.example/icons/lumen.png")
        XCTAssertEqual(app.category?.name, "Продуктивность")
        XCTAssertEqual(app.rating, 4.7)
        XCTAssertEqual(app.ratingCount, 1280)
        XCTAssertEqual(app.sizeBytes, 48_211_968)
        XCTAssertEqual(app.minOs, "15.0")
        XCTAssertEqual(app.tintLight, "#0041DC")
        XCTAssertEqual(app.bgColor, "#EAF1FF")
        XCTAssertEqual(app.badge, .new)
        XCTAssertTrue(app.isAvailable)
    }

    func testAppSummaryWithNullsAndUnknownValues() throws {
        let json = Fixtures.summary(id: "app_x", availability: "archived")
            .replacingOccurrences(of: "\"badge\": null", with: "\"badge\": \"hot\"")
        let app = try decode(AppSummary.self, json)
        XCTAssertNil(app.rating)
        XCTAssertNil(app.iconUrl)
        XCTAssertEqual(app.badge, .unknown)
        XCTAssertEqual(app.availability, .unavailable)
    }

    func testCatalogApp() throws {
        let app = try decode(CatalogApp.self, Fixtures.catalogApp)
        XCTAssertEqual(app.summary.name, "Lumen Notes")
        XCTAssertEqual(app.summary.badge, .updated)
        XCTAssertEqual(app.descriptionText, "Быстрые заметки.")
        XCTAssertEqual(app.whatsNew, "Исправления")
        XCTAssertEqual(app.bundleId, "com.lumenlabs.notes")
        XCTAssertEqual(app.ageRating, "4+")
        XCTAssertEqual(app.languages, ["RU", "EN"])
        XCTAssertNotNil(app.releasedAt)
        XCTAssertNotNil(app.updatedAt, "Даты с долями секунды тоже разбираются")
        XCTAssertEqual(app.screenshots.first?.width, 1290)
        XCTAssertEqual(app.info.first?.value, "Lumen Labs")
        XCTAssertEqual(app.similar.map(\.id), ["app_similar"])
    }

    func testGroupingsWithAllRoomStyles() throws {
        let response = try decode(GroupingsResponse.self, Fixtures.groupings)
        XCTAssertEqual(response.revision, 42)
        XCTAssertEqual(response.rooms.map(\.style), [.heroCarousel, .shelfOne, .shelfTwo, .chips, .unknown])

        let hero = response.rooms[0]
        XCTAssertEqual(hero.hero.count, 1)
        XCTAssertEqual(hero.hero.first?.headline, "Новое")
        XCTAssertEqual(hero.hero.first?.imageUrl?.absoluteString, "https://cdn.istore.example/hero.jpg")
        XCTAssertEqual(hero.hero.first?.gradient ?? [], ["#0041DC", "#92BDEF"])

        let shelf = response.rooms[1]
        XCTAssertEqual(shelf.title, "Выбор редакции")
        XCTAssertTrue(shelf.hasMore)
        XCTAssertEqual(shelf.items.count, 2)

        let cards = response.rooms[2]
        XCTAssertTrue(cards.hero.isEmpty, "Отсутствующие массивы становятся пустыми")
        XCTAssertTrue(cards.categories.isEmpty)

        let chips = response.rooms[3]
        XCTAssertEqual(chips.categories.first?.sfSymbol, "checkmark.circle")
    }

    func testRoomAndCategoryPages() throws {
        let room = try decode(RoomPage.self, Fixtures.roomPage)
        XCTAssertEqual(room.room.style, .shelfOne)
        XCTAssertEqual(room.nextCursor, "c2")

        let category = try decode(CategoryPage.self, Fixtures.categoryPage)
        XCTAssertEqual(category.category.id, "productivity")
        XCTAssertNil(category.nextCursor)
    }

    func testVersionsAcceptStringAndNumberBuild() throws {
        let page = try decode(Page<AppVersion>.self, Fixtures.versions)
        XCTAssertEqual(page.items.map(\.build), ["320", "310"])
        XCTAssertEqual(page.items.first?.sizeBytes, 48_211_968)
        XCTAssertNil(page.items.last?.notes)
    }

    func testAccountAndActivation() throws {
        let response = try decode(ActivateResponse.self, Fixtures.activateResponse)
        XCTAssertEqual(response.token, "tok_123")
        XCTAssertEqual(response.account.plan?.periodMonths, 1)
        XCTAssertEqual(response.account.status, .active)
        XCTAssertTrue(response.account.isActive)
        XCTAssertEqual(response.account.renewUrl?.host, "istore.example")
    }

    func testProfile() throws {
        let profile = try decode(ClientProfile.self, Fixtures.profile)
        XCTAssertEqual(profile.device?.installIdLast4, "a1b2")
        XCTAssertEqual(profile.device?.osVersion, "18.1")
        XCTAssertEqual(profile.client?.locale, "ru")
    }

    func testStoreState() throws {
        let open = try decode(StoreState.self, Fixtures.storeOpen)
        XCTAssertTrue(open.isOpen)
        XCTAssertNil(open.closed)

        let closed = try decode(StoreState.self, Fixtures.storeClosed)
        XCTAssertFalse(closed.isOpen)
        XCTAssertEqual(closed.closed?.title, "Техработы")
        XCTAssertNotNil(closed.closed?.reopensAt)
        XCTAssertEqual(closed.closed?.links.first?.url.absoluteString, "https://t.me/istore")
    }

    func testClientVersion() throws {
        let version = try decode(ClientVersion.self, Fixtures.clientVersion)
        XCTAssertEqual(version.latestBuild, 120)
        XCTAssertEqual(version.minSupportedBuild, 100)
        XCTAssertTrue(version.updateAvailable)
        XCTAssertFalse(version.mandatory)
        XCTAssertEqual(version.updateUrl?.scheme, "itms-services")
    }

    func testInstallGrant() throws {
        let grant = try decode(InstallGrant.self, Fixtures.grant(status: "ready"))
        XCTAssertEqual(grant.installId, "ins_1")
        XCTAssertEqual(grant.status, .ready)
        XCTAssertEqual(grant.itmsUrl?.scheme, "itms-services")
        XCTAssertNotNil(grant.manifestUrl)
        XCTAssertNil(grant.errorCode)

        let failed = try decode(InstallGrant.self, Fixtures.grant(status: "failed", itms: false, errorCode: "no_build"))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.errorCode, "no_build")
        XCTAssertNil(failed.itmsUrl)
    }

    func testChanges() throws {
        let response = try decode(ChangesResponse.self, Fixtures.changes)
        XCTAssertEqual(response.revision, 45)
        XCTAssertEqual(response.changes.map(\.kind), [.appUpsert, .appRemoved, .roomsChanged])
        XCTAssertEqual(response.changes.first?.app?.id, "app_a")
        XCTAssertEqual(response.changes[1].appId, "app_b")
        XCTAssertFalse(response.hasMore)
        XCTAssertFalse(response.reset)
    }

    func testSearchAndHints() throws {
        let search = try decode(SearchResponse.self, Fixtures.search)
        XCTAssertEqual(search.correctedQuery, "lumen")
        XCTAssertEqual(search.nextCursor, "n1")

        let hints = try decode(SearchHintsResponse.self, Fixtures.hints)
        XCTAssertEqual(hints.hints.count, 2)
        XCTAssertEqual(hints.hints.first?.appId, "app_a")
        XCTAssertNil(hints.hints.last?.appId)
    }

    func testErrorEnvelope() throws {
        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: Fixtures.error.data)
        XCTAssertEqual(envelope.error.code, "invalid_code")
        XCTAssertEqual(envelope.error.message, "Код не найден")
    }

    func testRequestBodiesUseSnakeCaseAndExplicitNulls() throws {
        let encoder = JSONCoding.makeEncoder()
        let install = try encoder.encode(InstallRequestBody(appId: "app_a", version: nil))
        let installObject = try XCTUnwrap(JSONSerialization.jsonObject(with: install) as? [String: Any])
        XCTAssertEqual(installObject["app_id"] as? String, "app_a")
        XCTAssertTrue(installObject.keys.contains("version"))
        XCTAssertTrue(installObject["version"] is NSNull)

        let activation = try encoder.encode(ActivateRequest(
            activationCode: "DEMO-DEMO-0001",
            device: ActivationDevice(installId: "uuid", model: "iPhone16,2", osVersion: "18.1", locale: "ru_RU")
        ))
        let activationObject = try XCTUnwrap(JSONSerialization.jsonObject(with: activation) as? [String: Any])
        XCTAssertEqual(activationObject["activation_code"] as? String, "DEMO-DEMO-0001")
        let device = try XCTUnwrap(activationObject["device"] as? [String: Any])
        XCTAssertEqual(device["install_id"] as? String, "uuid")
        XCTAssertEqual(device["os_version"] as? String, "18.1")

        let event = try encoder.encode(InstallEventBody(stage: InstallStage.handingOff.rawValue, errorCode: nil))
        let eventObject = try XCTUnwrap(JSONSerialization.jsonObject(with: event) as? [String: Any])
        XCTAssertEqual(eventObject["stage"] as? String, "handing_off")
        XCTAssertTrue(eventObject["error_code"] is NSNull)
    }
}
