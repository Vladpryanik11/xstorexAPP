import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Один параметр строки запроса. Свой тип вместо `URLQueryItem`, чтобы `Endpoint` был гарантированно `Sendable`.
struct QueryParam: Hashable, Sendable {
    let name: String
    let value: String?

    init(_ name: String, _ value: String?) {
        self.name = name
        self.value = value
    }
}

/// Пустой ответ (`202`, `204`).
struct EmptyResponse: Codable, Sendable, Equatable {}

/// Описание запроса к API. `Response` — тип, в который декодируется тело ответа.
struct Endpoint<Response>: Sendable {
    var path: String
    var method: HTTPMethod
    var query: [QueryParam]
    var body: Data?
    var requiresAuth: Bool
    /// Использовать ETag-кэш в памяти (`If-None-Match`). Только для GET каталога.
    var usesETag: Bool
    var timeout: TimeInterval?

    init(
        path: String,
        method: HTTPMethod = .get,
        query: [QueryParam] = [],
        body: Data? = nil,
        requiresAuth: Bool = true,
        usesETag: Bool = false,
        timeout: TimeInterval? = nil
    ) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.usesETag = usesETag
        self.timeout = timeout
    }

    /// POST/PUT с JSON-телом.
    static func json<Body: Encodable>(
        path: String,
        method: HTTPMethod = .post,
        body: Body,
        requiresAuth: Bool = true
    ) -> Endpoint<Response> {
        let data = try? JSONCoding.makeEncoder().encode(body)
        return Endpoint<Response>(path: path, method: method, body: data, requiresAuth: requiresAuth)
    }
}

/// Курсорная пагинация: `cursor` и `limit` в строке запроса.
enum Paging {
    static func params(cursor: String?, limit: Int?) -> [QueryParam] {
        var result: [QueryParam] = []
        if let cursor = cursor, !cursor.isEmpty {
            result.append(QueryParam("cursor", cursor))
        }
        if let limit = limit {
            result.append(QueryParam("limit", String(max(1, min(50, limit)))))
        }
        return result
    }
}

/// Кодирование и декодирование JSON по правилам API.md: snake_case, ISO 8601.
enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISODate(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO 8601 date: \(raw)"
            )
        }
        return decoder
    }

    /// Тела запросов описывают ключи явно (`CodingKeys` в snake_case), поэтому стратегия ключей не нужна.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatISODate(date))
        }
        return encoder
    }

    static func parseISODate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func formatISODate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
