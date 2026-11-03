import Foundation

/// Профиль, состояние магазина и запросы приложений (`/client/*`, `/search/requests`).
protocol ClientServicing: Sendable {
    func profile() async throws -> ClientProfile
    func storeState() async throws -> StoreState
}

struct ClientService: ClientServicing {
    let api: APIClientProtocol

    func profile() async throws -> ClientProfile {
        try await api.send(Endpoint<ClientProfile>(path: "/client/profile"))
    }

    func storeState() async throws -> StoreState {
        try await api.send(Endpoint<StoreState>(path: "/client/store-state", requiresAuth: false))
    }
}
