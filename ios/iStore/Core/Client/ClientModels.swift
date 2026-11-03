import Foundation

// MARK: - Account

struct Plan: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let periodMonths: Int?
}

enum AccountStatus: String, Codable, Sendable {
    case active
    case expired
    case suspended
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AccountStatus(rawValue: raw) ?? .unknown
    }
}

/// Account (API.md, «Общие схемы»).
struct Account: Codable, Hashable, Sendable {
    let id: String
    let displayName: String?
    let plan: Plan?
    let status: AccountStatus
    let expiresAt: Date?
    let renewUrl: URL?
    let createdAt: Date?

    var isActive: Bool { status == .active }
}

// MARK: - Auth

struct ActivationDevice: Encodable, Sendable {
    let installId: String
    let model: String
    let osVersion: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case installId = "install_id"
        case model
        case osVersion = "os_version"
        case locale
    }
}

struct ActivateRequest: Encodable, Sendable {
    let activationCode: String
    let device: ActivationDevice

    enum CodingKeys: String, CodingKey {
        case activationCode = "activation_code"
        case device
    }
}

struct ActivateResponse: Decodable, Sendable {
    let token: String
    let account: Account
}

// MARK: - Client

struct DeviceProfile: Decodable, Hashable, Sendable {
    let id: String?
    let model: String?
    let osVersion: String?
    let installIdLast4: String?
}

struct ClientMeta: Decodable, Hashable, Sendable {
    let locale: String?
    let lastSeen: Date?
}

/// `GET /client/profile`.
struct ClientProfile: Decodable, Sendable {
    let account: Account
    let device: DeviceProfile?
    let client: ClientMeta?
}

struct StoreLink: Codable, Hashable, Sendable {
    let title: String
    let url: URL
}

struct StoreClosure: Decodable, Hashable, Sendable {
    let title: String?
    let message: String?
    let reopensAt: Date?
    let links: [StoreLink]

    enum CodingKeys: String, CodingKey {
        case title, message, reopensAt, links
    }

    init(title: String?, message: String?, reopensAt: Date?, links: [StoreLink]) {
        self.title = title
        self.message = message
        self.reopensAt = reopensAt
        self.links = links
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        reopensAt = try container.decodeIfPresent(Date.self, forKey: .reopensAt)
        links = try container.decodeIfPresent([StoreLink].self, forKey: .links) ?? []
    }
}

/// `GET /client/store-state`.
struct StoreState: Decodable, Hashable, Sendable {
    let state: String
    let closed: StoreClosure?

    var isOpen: Bool { state != "closed" }
}

/// `GET /client/version`.
struct ClientVersion: Decodable, Hashable, Sendable {
    let latestVersion: String
    let latestBuild: Int
    let minSupportedBuild: Int
    let updateAvailable: Bool
    let mandatory: Bool
    let releaseNotes: String?
    let updateUrl: URL?
}

// MARK: - Telemetry

struct TelemetryEvent: Encodable, Sendable, Equatable {
    let kind: String
    let ts: String
    let props: [String: String]
}

struct TelemetryBatch: Encodable, Sendable {
    let events: [TelemetryEvent]
}
