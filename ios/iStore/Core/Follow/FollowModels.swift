import Foundation

/// `FollowStatus` — подписка аккаунта на обновления приложения (API.md, раздел Follows).
struct FollowStatus: Decodable, Hashable, Sendable {
    let appId: String
    let following: Bool
    let muted: Bool
    let followerCount: Int
}

/// Строка списка `GET /client/follows`.
struct FollowedApp: Decodable, Hashable, Sendable {
    let app: AppSummary
    let muted: Bool
    let followedAt: Date?
}

struct FollowMuteBody: Encodable, Sendable {
    let muted: Bool

    enum CodingKeys: String, CodingKey {
        case muted
    }
}
