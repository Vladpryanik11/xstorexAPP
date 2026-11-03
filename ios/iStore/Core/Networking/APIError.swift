import Foundation

/// Ошибка API, приведённая к виду, удобному для UI и телеметрии.
/// Маппинг строится по `error.code` из тела ответа и HTTP-статусу (API.md, «Общие правила»).
enum APIError: Error, Equatable, Sendable {
    /// `401 unauthorized`: токен недействителен, клиент разлогинивается.
    case unauthorized
    /// `401 grant_expired`: истёк грант установки, нужен новый. Токен при этом действителен.
    case grantExpired
    /// `403 account_inactive`: подписка закончилась или аккаунт приостановлен.
    case accountInactive
    /// `404`: `not_found`, `invalid_code` и т. п.
    case notFound(code: String)
    /// `409`: `code_used`, `no_build`, `conflict`.
    case conflict(code: String)
    /// `429 rate_limited`.
    case rateLimited(retryAfter: TimeInterval?)
    /// `400 invalid_request` и прочие 4xx.
    case invalidRequest(code: String, message: String?)
    /// `5xx`.
    case server(status: Int, code: String?)
    /// Нет подключения к интернету.
    case offline
    /// Истекло время ожидания.
    case timedOut
    /// Прочие транспортные ошибки (`URLError.Code.rawValue`).
    case transport(code: Int)
    /// Тело ответа не соответствует контракту.
    case decoding(String)
    /// Ответ без HTTP-статуса или с неожиданным статусом.
    case invalidResponse(status: Int)
    case cancelled

    /// Короткий машинный код для телеметрии и `error_code` в событиях установки.
    var code: String {
        switch self {
        case .unauthorized: return "unauthorized"
        case .grantExpired: return "grant_expired"
        case .accountInactive: return "account_inactive"
        case .notFound(let code): return code
        case .conflict(let code): return code
        case .rateLimited: return "rate_limited"
        case .invalidRequest(let code, _): return code
        case .server(_, let code): return code ?? "internal"
        case .offline: return "offline"
        case .timedOut: return "timed_out"
        case .transport(let code): return "transport_\(code)"
        case .decoding: return "invalid_response"
        case .invalidResponse: return "invalid_response"
        case .cancelled: return "cancelled"
        }
    }

    /// Строит ошибку по HTTP-статусу и телу ответа.
    static func from(status: Int, body: Data?, retryAfterHeader: String?) -> APIError {
        let envelope = body.flatMap { try? JSONDecoder().decode(APIErrorEnvelope.self, from: $0) }
        let code = envelope?.error.code
        let message = envelope?.error.message

        if code == "account_inactive" {
            return .accountInactive
        }
        switch status {
        case 401:
            // Разлогин только на `unauthorized`: `grant_expired` относится к гранту установки.
            if code == "grant_expired" {
                return .grantExpired
            }
            return .unauthorized
        case 403:
            if let code = code {
                return APIError.invalidRequest(code: code, message: message)
            }
            return APIError.accountInactive
        case 404:
            return .notFound(code: code ?? "not_found")
        case 409:
            return .conflict(code: code ?? "conflict")
        case 416:
            return .invalidRequest(code: code ?? "range_not_satisfiable", message: message)
        case 429:
            let seconds = retryAfterHeader.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
            return .rateLimited(retryAfter: seconds)
        case 400..<500:
            return .invalidRequest(code: code ?? "invalid_request", message: message)
        case 500..<600:
            return .server(status: status, code: code)
        default:
            return .invalidResponse(status: status)
        }
    }

    /// Приводит ошибку транспорта (`URLError`, отмена) к `APIError`.
    static func from(transportError error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        if error is CancellationError {
            return .cancelled
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .offline
            case .timedOut:
                return .timedOut
            case .cancelled:
                return .cancelled
            default:
                return .transport(code: urlError.code.rawValue)
            }
        }
        return .transport(code: -1)
    }
}

/// Тело ошибки: `{"error": {"code": "…", "message": "…"}}`.
struct APIErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let code: String
        let message: String?
    }

    let error: Body
}
