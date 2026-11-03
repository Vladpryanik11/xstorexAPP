import Foundation

protocol ClientUpdateChecking: Sendable {
    func check(build: Int) async throws -> ClientVersion
}

/// `GET /client/version?build=` на старте приложения.
struct ClientUpdateService: ClientUpdateChecking {
    let api: APIClientProtocol

    func check(build: Int) async throws -> ClientVersion {
        try await api.send(Endpoint<ClientVersion>(
            path: "/client/version",
            query: [QueryParam("build", String(build))],
            requiresAuth: false
        ))
    }
}

/// Помнит, какую необязательную версию пользователь отложил, чтобы не показывать шит на каждом запуске.
struct ClientUpdatePreferences {
    private static let key = "client_update.dismissed_build"
    let defaults: UserDefaults

    func isDismissed(build: Int) -> Bool {
        defaults.integer(forKey: Self.key) >= build
    }

    func markDismissed(build: Int) {
        defaults.set(build, forKey: Self.key)
    }
}
