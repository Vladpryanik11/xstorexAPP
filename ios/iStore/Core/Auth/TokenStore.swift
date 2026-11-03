import Foundation

/// Хранилище Bearer-токена.
protocol TokenStoring: Sendable {
    func token() async -> String?
    func save(_ token: String) async
    func clear() async
}

/// Токен в Keychain с кэшем в памяти.
actor KeychainTokenStore: TokenStoring {
    private static let account = "bearer-token"

    private let keychain: KeychainStore
    private var cached: String?
    private var didLoad = false

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func token() -> String? {
        if !didLoad {
            cached = keychain.string(for: Self.account)
            didLoad = true
        }
        return cached
    }

    func save(_ token: String) {
        keychain.set(token, for: Self.account)
        cached = token
        didLoad = true
    }

    func clear() {
        keychain.remove(Self.account)
        cached = nil
        didLoad = true
    }
}

/// Токен только в памяти: для тестов и превью.
actor InMemoryTokenStore: TokenStoring {
    private var value: String?

    init(token: String? = nil) {
        value = token
    }

    func token() -> String? { value }
    func save(_ token: String) { value = token }
    func clear() { value = nil }
}

/// UUID установки (`X-Install-Id`). Генерируется при первом запуске и живёт в Keychain,
/// поэтому переживает переустановку приложения на том же устройстве.
enum InstallID {
    private static let account = "install-id"

    static func load(from keychain: KeychainStore) -> String {
        if let existing = keychain.string(for: account), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        keychain.set(fresh, for: account)
        return fresh
    }
}
