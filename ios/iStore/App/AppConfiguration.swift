import Foundation

/// Конфигурация сборки: адрес API из `Info.plist` (`IStoreAPIBaseURL`), окружение APNs, версия и номер сборки.
struct AppConfiguration: Sendable {
    static let fallbackBaseURL = URL(string: "http://localhost:8080")!

    let baseURL: URL
    let version: String
    let build: String
    /// `sandbox` или `production`: то же окружение, что в entitlement `aps-environment` этой сборки.
    var apnsEnvironment: String = AppConfiguration.defaultAPNsEnvironment

    var buildNumber: Int { Int(build) ?? 0 }

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        var raw = bundle.object(forInfoDictionaryKey: "IStoreAPIBaseURL") as? String
        #if DEBUG
        // В Debug адрес можно переопределить переменной окружения схемы.
        if let override = environment["ISTORE_API_BASE_URL"], !override.isEmpty {
            raw = override
        }
        #endif
        var baseURL = fallbackBaseURL
        if let raw = raw, !raw.contains("$("), let url = URL(string: raw), url.scheme != nil {
            baseURL = url
        }
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        var configuration = AppConfiguration(baseURL: baseURL, version: version, build: build)
        switch bundle.object(forInfoDictionaryKey: "IStoreAPSEnvironment") as? String {
        case "development": configuration.apnsEnvironment = "sandbox"
        case "production": configuration.apnsEnvironment = "production"
        default: break
        }
        return configuration
    }

    static var defaultAPNsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
