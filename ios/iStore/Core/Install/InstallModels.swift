import Foundation

enum GrantStatus: String, Codable, Sendable {
    case preparing
    case ready
    case failed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GrantStatus(rawValue: raw) ?? .unknown
    }
}

/// InstallGrant (API.md, «Installs»).
struct InstallGrant: Decodable, Hashable, Sendable {
    let installId: String
    let appId: String
    let version: String?
    let status: GrantStatus
    let errorCode: String?
    let manifestUrl: URL?
    let itmsUrl: URL?
    let sizeBytes: Int64?
    let sha256: String?
    let expiresAt: Date?
}

struct InstallRequestBody: Encodable, Sendable {
    let appId: String
    let version: String?

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case version
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appId, forKey: .appId)
        try container.encode(version, forKey: .version)
    }
}

/// Стадия для `POST /catalog/installs/{id}/events`.
enum InstallStage: String, Sendable {
    case preparing
    case ready
    case handingOff = "handing_off"
    case installing
    case failed
}

struct InstallEventBody: Encodable, Sendable {
    let stage: String
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case stage
        case errorCode = "error_code"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage, forKey: .stage)
        try container.encode(errorCode, forKey: .errorCode)
    }
}

/// Состояние установки одного приложения.
/// `idle → preparing → ready → handingOff → installing | failed(code)`.
enum InstallState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case handingOff
    case installing
    case failed(code: String)

    /// Установка идёт: повторный старт игнорируется.
    var isActive: Bool {
        switch self {
        case .preparing, .ready, .handingOff, .installing:
            return true
        case .idle, .failed:
            return false
        }
    }

    /// Доля для кольца прогресса; `nil` — неопределённый спиннер.
    var progress: Double? {
        switch self {
        case .idle, .failed: return 0
        case .preparing: return nil
        case .ready: return 0.5
        case .handingOff: return 0.8
        case .installing: return 1
        }
    }
}

/// Коды ошибок установки, которые клиент ставит сам.
enum InstallErrorCode {
    static let incompatibleDevice = "incompatible_device"
    static let insufficientSpace = "insufficient_space"
    static let installURLMissing = "install_url_missing"
    static let launchFailed = "launch_failed"
    static let timedOut = "install_timed_out"
    static let appNotAvailable = "app_not_available"
    static let noBuild = "no_build"
    static let accountInactive = "account_inactive"
    static let offline = "offline"
    static let generic = "generic"
}

/// Итог проверки до старта.
enum InstallPreflight: Equatable, Sendable {
    case ok
    case incompatible(requiredOS: String)
    case lowSpace(requiredBytes: Int64, freeBytes: Int64)
    case unavailable
}
