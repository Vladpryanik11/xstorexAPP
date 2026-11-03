import XCTest
@testable import iStore

final class FollowServiceTests: XCTestCase {
    private static func status(following: Bool, muted: Bool = false, count: Int = 1) -> String {
        """
        { "app_id": "app_a", "following": \(following), "muted": \(muted), "follower_count": \(count) }
        """
    }

    private static let followedPage = """
    {
      "items": [{ "app": \(Fixtures.summary(id: "app_a")), "muted": true, "followed_at": "2026-11-03T12:00:00Z" }],
      "next_cursor": "c1"
    }
    """

    func testRoutesAndDecoding() async throws {
        let api = MockAPIClient { method, path, _ in
            switch (method, path) {
            case (.get, "/apps/app_a/follow"), (.delete, "/apps/app_a/follow"):
                return FollowServiceTests.status(following: false, count: 0)
            case (.post, "/apps/app_a/follow"):
                return FollowServiceTests.status(following: true)
            case (.put, "/apps/app_a/follow/mute"):
                return FollowServiceTests.status(following: true, muted: true)
            case (.get, "/client/follows"):
                return FollowServiceTests.followedPage
            default:
                throw URLError(.unsupportedURL)
            }
        }
        let service = FollowService(api: api)

        let initial = try await service.status(appId: "app_a")
        XCTAssertEqual(initial, FollowStatus(appId: "app_a", following: false, muted: false, followerCount: 0))
        let followed = try await service.follow(appId: "app_a")
        XCTAssertTrue(followed.following)
        XCTAssertEqual(followed.followerCount, 1)
        let muted = try await service.setMuted(true, appId: "app_a")
        XCTAssertTrue(muted.muted)
        let unfollowed = try await service.unfollow(appId: "app_a")
        XCTAssertFalse(unfollowed.following)

        let page = try await service.followedApps(cursor: nil)
        XCTAssertEqual(page.items.map(\.app.id), ["app_a"])
        XCTAssertEqual(page.items.first?.muted, true)
        XCTAssertNotNil(page.items.first?.followedAt)
        XCTAssertEqual(page.nextCursor, "c1")

        XCTAssertEqual(api.recordedCalls.map { "\($0.0.rawValue) \($0.1)" }, [
            "GET /apps/app_a/follow",
            "POST /apps/app_a/follow",
            "PUT /apps/app_a/follow/mute",
            "DELETE /apps/app_a/follow",
            "GET /client/follows"
        ])
    }

    func testMuteBodyEncoding() throws {
        let data = try JSONCoding.makeEncoder().encode(FollowMuteBody(muted: true))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"muted":true}"#)
    }
}
