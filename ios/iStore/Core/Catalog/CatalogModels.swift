import Foundation

// MARK: - AppSummary

struct CategoryRef: Codable, Hashable, Sendable {
    let id: String
    let name: String
}

enum AppBadge: String, Codable, Sendable {
    case new
    case updated
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppBadge(rawValue: raw) ?? .unknown
    }
}

enum AppAvailability: String, Codable, Sendable {
    case available
    case unavailable

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AppAvailability(rawValue: raw) ?? .unavailable
    }
}

/// AppSummary — строка полки, результат поиска (API.md).
struct AppSummary: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String?
    let iconUrl: URL?
    let category: CategoryRef?
    let rating: Double?
    let ratingCount: Int?
    let version: String
    let sizeBytes: Int64
    let minOs: String
    let tintLight: String?
    let tintDark: String?
    let bgColor: String?
    let badge: AppBadge?
    let availability: AppAvailability

    var isAvailable: Bool { availability == .available }
}

// MARK: - CatalogApp

struct Screenshot: Codable, Hashable, Sendable {
    let url: URL
    let width: Int
    let height: Int
}

struct InfoRow: Codable, Hashable, Sendable {
    let label: String
    let value: String
}

/// CatalogApp — карточка приложения: все поля AppSummary плюс подробности.
struct CatalogApp: Decodable, Hashable, Sendable {
    let summary: AppSummary
    let descriptionText: String
    let whatsNew: String?
    let developer: String?
    let bundleId: String?
    let ageRating: String?
    let languages: [String]
    let releasedAt: Date?
    let updatedAt: Date?
    let screenshots: [Screenshot]
    let info: [InfoRow]
    let similar: [AppSummary]

    var id: String { summary.id }

    enum CodingKeys: String, CodingKey {
        case descriptionText = "description"
        case whatsNew, developer, bundleId, ageRating, languages, releasedAt, updatedAt, screenshots, info, similar
    }

    init(from decoder: Decoder) throws {
        summary = try AppSummary(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        descriptionText = try container.decodeIfPresent(String.self, forKey: .descriptionText) ?? ""
        whatsNew = try container.decodeIfPresent(String.self, forKey: .whatsNew)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        ageRating = try container.decodeIfPresent(String.self, forKey: .ageRating)
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
        releasedAt = try container.decodeIfPresent(Date.self, forKey: .releasedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        screenshots = try container.decodeIfPresent([Screenshot].self, forKey: .screenshots) ?? []
        info = try container.decodeIfPresent([InfoRow].self, forKey: .info) ?? []
        similar = try container.decodeIfPresent([AppSummary].self, forKey: .similar) ?? []
    }
}

// MARK: - Rooms

enum RoomStyle: String, Codable, Sendable {
    case heroCarousel = "hero_carousel"
    case shelfOne = "shelf_one"
    case shelfTwo = "shelf_two"
    case chips
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RoomStyle(rawValue: raw) ?? .unknown
    }
}

/// Чип категории в комнате стиля `chips`.
struct CategoryChip: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let sfSymbol: String?
}

/// HeroCard — карточка hero-карусели.
struct HeroCard: Codable, Hashable, Sendable {
    let app: AppSummary
    let headline: String?
    let title: String?
    let imageUrl: URL?
    let gradient: [String]?
}

/// Room — секция витрины.
struct Room: Codable, Hashable, Sendable {
    let id: String
    let style: RoomStyle
    let title: String?
    let subtitle: String?
    var items: [AppSummary]
    var hero: [HeroCard]
    let categories: [CategoryChip]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case id, style, title, subtitle, items, hero, categories, hasMore
    }

    init(
        id: String,
        style: RoomStyle,
        title: String?,
        subtitle: String?,
        items: [AppSummary],
        hero: [HeroCard],
        categories: [CategoryChip],
        hasMore: Bool
    ) {
        self.id = id
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.hero = hero
        self.categories = categories
        self.hasMore = hasMore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        style = try container.decode(RoomStyle.self, forKey: .style)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        items = try container.decodeIfPresent([AppSummary].self, forKey: .items) ?? []
        hero = try container.decodeIfPresent([HeroCard].self, forKey: .hero) ?? []
        categories = try container.decodeIfPresent([CategoryChip].self, forKey: .categories) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
    }
}

/// `GET /groupings?tab=`.
struct GroupingsResponse: Decodable, Sendable {
    let tab: String
    let revision: Int
    let rooms: [Room]
}

struct RoomRef: Decodable, Hashable, Sendable {
    let id: String
    let title: String?
    let style: RoomStyle
}

/// `GET /groupings/{room_id}` — экран «Показать все».
struct RoomPage: Decodable, Sendable {
    let room: RoomRef
    let items: [AppSummary]
    let nextCursor: String?
}

/// `GET /catalog/categories/{id}`.
struct CategoryPage: Decodable, Sendable {
    let category: CategoryRef
    let items: [AppSummary]
    let nextCursor: String?
}

/// Общая страница: `{"items": [...], "next_cursor": ...}`.
struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let nextCursor: String?
}

/// Запись истории версий.
struct AppVersion: Decodable, Hashable, Sendable {
    let version: String
    let build: String?
    let releasedAt: Date?
    let notes: String?
    let sizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case version, build, releasedAt, notes, sizeBytes
    }

    init(version: String, build: String?, releasedAt: Date?, notes: String?, sizeBytes: Int64?) {
        self.version = version
        self.build = build
        self.releasedAt = releasedAt
        self.notes = notes
        self.sizeBytes = sizeBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        // `build` может прийти числом или строкой.
        if let number = try? container.decodeIfPresent(Int.self, forKey: .build) {
            build = String(number)
        } else {
            build = try? container.decodeIfPresent(String.self, forKey: .build)
        }
        releasedAt = try container.decodeIfPresent(Date.self, forKey: .releasedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
    }
}

// MARK: - Changes

enum ChangeKind: String, Codable, Sendable {
    case appUpsert = "app_upsert"
    case appRemoved = "app_removed"
    case roomsChanged = "rooms_changed"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChangeKind(rawValue: raw) ?? .unknown
    }
}

/// Change — запись журнала изменений каталога.
struct CatalogChange: Codable, Hashable, Sendable {
    let revision: Int
    let kind: ChangeKind
    let appId: String?
    let app: AppSummary?
}

/// `GET /catalog/changes?since=`.
struct ChangesResponse: Decodable, Sendable {
    let revision: Int
    let changes: [CatalogChange]
    let hasMore: Bool
    let reset: Bool
}

/// `data` событий `hello` и `reset`.
struct RevisionPayload: Decodable, Sendable, Equatable {
    let revision: Int
}

// MARK: - Search

struct SearchResponse: Decodable, Sendable {
    let items: [AppSummary]
    let nextCursor: String?
    let correctedQuery: String?
}

struct SearchHint: Decodable, Hashable, Sendable {
    let text: String
    let appId: String?
}

struct SearchHintsResponse: Decodable, Sendable {
    let hints: [SearchHint]
}

struct SearchRequestBody: Encodable, Sendable {
    let query: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case query, note
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query, forKey: .query)
        try container.encode(note, forKey: .note)
    }
}
