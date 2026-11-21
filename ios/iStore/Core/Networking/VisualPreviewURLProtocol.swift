import Foundation

/// Отдаёт локальные данные каталога для отдельной демонстрационной сборки.
final class VisualPreviewURLProtocol: URLProtocol, @unchecked Sendable {
    private static let host = "xstore-preview.invalid"

    private static let fixtures: [String: [String: Any]] = {
        guard let url = Bundle.main.url(forResource: "VisualPreview", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let routes = object as? [String: [String: Any]] else { return [:] }
        return routes
    }()

    static func configure(_ configuration: URLSessionConfiguration) {
        #if XSTORE_VISUAL_PREVIEW
        configuration.protocolClasses = [VisualPreviewURLProtocol.self]
        #endif
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        let result = response(for: url)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: result.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": result.type]
        ) else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: result.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func response(for url: URL) -> (status: Int, type: String, data: Data) {
        let path = url.path
        if path.hasPrefix("/static/"), path.hasSuffix(".png") {
            let key = url.pathComponents.dropFirst(2).joined(separator: "-")
            if let resource = Bundle.main.url(forResource: "preview-" + key, withExtension: nil),
               let data = try? Data(contentsOf: resource) {
                return (200, "image/png", data)
            }
            return json(status: 404, ["error": ["code": "not_found"]])
        }

        guard request.httpMethod == "GET" else {
            return json(status: 409, ["error": ["code": "no_build"]])
        }
        let language = request.value(forHTTPHeaderField: "Accept-Language") ?? "en"
        let routes = Self.fixtures[language] ?? Self.fixtures["en"] ?? [:]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if path == "/api/v1/groupings", let tab = query.first(where: { $0.name == "tab" })?.value,
           let value = routes["\(path)?tab=\(tab)"] {
            return json(value)
        }
        if let value = routes[path] { return json(value) }

        switch path {
        case "/api/v1/search", "/api/v1/search/hints":
            let phrase = query.first(where: { $0.name == "q" })?.value ?? ""
            let apps = routes.compactMap { key, value -> [String: Any]? in
                guard key.hasPrefix("/api/v1/catalog/apps/"), !key.hasSuffix("/versions") else { return nil }
                return value as? [String: Any]
            }
            let matches = apps.filter { app in
                !phrase.isEmpty && ["name", "subtitle", "developer"].contains {
                    (app[$0] as? String)?.localizedCaseInsensitiveContains(phrase) == true
                }
            }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
            if path.hasSuffix("/hints") {
                let hints = matches.prefix(8).compactMap { app -> [String: String]? in
                    guard let name = app["name"] as? String, let id = app["id"] as? String else { return nil }
                    return ["text": name, "app_id": id]
                }
                return json(["hints": hints])
            }
            return json(["items": matches, "next_cursor": NSNull(), "corrected_query": NSNull()])
        case "/api/v1/catalog/stream", "/api/v1/client/profile":
            return json(status: 401, ["error": ["code": "unauthorized"]])
        default:
            if path.hasSuffix("/follow") {
                return json(["following": false, "muted": false])
            }
            return json(status: 404, ["error": ["code": "not_found"]])
        }
    }

    private func json(status: Int = 200, _ value: Any) -> (Int, String, Data) {
        (status, "application/json", (try? JSONSerialization.data(withJSONObject: value)) ?? Data())
    }
}
