import Foundation

enum StorefrontTab: String, CaseIterable, Sendable {
    case today
    case games
    case apps
}

/// Чтение каталога и поиска. Экраны зависят от протокола, чтобы их можно было тестировать.
protocol CatalogServicing: Sendable {
    func groupings(tab: StorefrontTab) async throws -> GroupingsResponse
    func roomPage(id: String, cursor: String?) async throws -> RoomPage
    func categoryPage(id: String, cursor: String?) async throws -> CategoryPage
    func app(id: String) async throws -> CatalogApp
    func versions(appId: String, cursor: String?) async throws -> Page<AppVersion>
    func changes(since revision: Int) async throws -> ChangesResponse
    func search(query: String, cursor: String?) async throws -> SearchResponse
    func hints(query: String) async throws -> [SearchHint]
    func requestApp(query: String, note: String?) async throws
}

struct CatalogService: CatalogServicing {
    static let pageSize = 20

    let api: APIClientProtocol

    func groupings(tab: StorefrontTab) async throws -> GroupingsResponse {
        try await api.send(Endpoint<GroupingsResponse>(
            path: "/groupings",
            query: [QueryParam("tab", tab.rawValue)],
            usesETag: true
        ))
    }

    func roomPage(id: String, cursor: String?) async throws -> RoomPage {
        try await api.send(Endpoint<RoomPage>(
            path: "/groupings/\(id)",
            query: Paging.params(cursor: cursor, limit: Self.pageSize),
            usesETag: true
        ))
    }

    func categoryPage(id: String, cursor: String?) async throws -> CategoryPage {
        try await api.send(Endpoint<CategoryPage>(
            path: "/catalog/categories/\(id)",
            query: Paging.params(cursor: cursor, limit: Self.pageSize),
            usesETag: true
        ))
    }

    func app(id: String) async throws -> CatalogApp {
        try await api.send(Endpoint<CatalogApp>(path: "/catalog/apps/\(id)", usesETag: true))
    }

    func versions(appId: String, cursor: String?) async throws -> Page<AppVersion> {
        try await api.send(Endpoint<Page<AppVersion>>(
            path: "/catalog/apps/\(appId)/versions",
            query: Paging.params(cursor: cursor, limit: Self.pageSize)
        ))
    }

    func changes(since revision: Int) async throws -> ChangesResponse {
        try await api.send(Endpoint<ChangesResponse>(
            path: "/catalog/changes",
            query: [QueryParam("since", String(revision)), QueryParam("limit", "500")]
        ))
    }

    func search(query: String, cursor: String?) async throws -> SearchResponse {
        try await api.send(Endpoint<SearchResponse>(
            path: "/search",
            query: [QueryParam("q", query)] + Paging.params(cursor: cursor, limit: Self.pageSize)
        ))
    }

    func hints(query: String) async throws -> [SearchHint] {
        let response = try await api.send(Endpoint<SearchHintsResponse>(
            path: "/search/hints",
            query: [QueryParam("q", query)]
        ))
        return response.hints
    }

    func requestApp(query: String, note: String?) async throws {
        let body = SearchRequestBody(query: query, note: note)
        _ = try await api.send(Endpoint<EmptyResponse>.json(path: "/search/requests", body: body))
    }
}
