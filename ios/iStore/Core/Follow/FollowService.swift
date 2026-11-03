import Foundation

/// Подписки на обновления приложений: кнопка в карточке и экран «Отслеживаемые».
protocol FollowServicing: Sendable {
    func status(appId: String) async throws -> FollowStatus
    func follow(appId: String) async throws -> FollowStatus
    func unfollow(appId: String) async throws -> FollowStatus
    func setMuted(_ muted: Bool, appId: String) async throws -> FollowStatus
    func followedApps(cursor: String?) async throws -> Page<FollowedApp>
}

struct FollowService: FollowServicing {
    static let pageSize = 20

    let api: APIClientProtocol

    func status(appId: String) async throws -> FollowStatus {
        try await api.send(Endpoint<FollowStatus>(path: "/apps/\(appId)/follow"))
    }

    func follow(appId: String) async throws -> FollowStatus {
        try await api.send(Endpoint<FollowStatus>(path: "/apps/\(appId)/follow", method: .post))
    }

    func unfollow(appId: String) async throws -> FollowStatus {
        try await api.send(Endpoint<FollowStatus>(path: "/apps/\(appId)/follow", method: .delete))
    }

    func setMuted(_ muted: Bool, appId: String) async throws -> FollowStatus {
        try await api.send(Endpoint<FollowStatus>.json(
            path: "/apps/\(appId)/follow/mute",
            method: .put,
            body: FollowMuteBody(muted: muted)
        ))
    }

    func followedApps(cursor: String?) async throws -> Page<FollowedApp> {
        try await api.send(Endpoint<Page<FollowedApp>>(
            path: "/client/follows",
            query: Paging.params(cursor: cursor, limit: Self.pageSize)
        ))
    }
}
