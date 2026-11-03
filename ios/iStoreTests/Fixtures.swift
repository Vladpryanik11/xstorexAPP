import Foundation
@testable import iStore

/// JSON-фикстуры по схемам API.md.
enum Fixtures {
    static let appSummary = """
    {
      "id": "app_7f3k2",
      "name": "Lumen Notes",
      "subtitle": "Заметки и списки",
      "icon_url": "https://cdn.istore.example/icons/lumen.png",
      "category": { "id": "productivity", "name": "Продуктивность" },
      "rating": 4.7,
      "rating_count": 1280,
      "version": "3.2.0",
      "size_bytes": 48211968,
      "min_os": "15.0",
      "tint_light": "#0041DC",
      "tint_dark": "#6AA2E3",
      "bg_color": "#EAF1FF",
      "badge": "new",
      "availability": "available"
    }
    """

    static func summary(id: String, minOS: String = "15.0", size: Int64 = 48211968, availability: String = "available") -> String {
        """
        {
          "id": "\(id)",
          "name": "App \(id)",
          "subtitle": null,
          "icon_url": null,
          "category": null,
          "rating": null,
          "rating_count": null,
          "version": "1.0",
          "size_bytes": \(size),
          "min_os": "\(minOS)",
          "tint_light": null,
          "tint_dark": null,
          "bg_color": null,
          "badge": null,
          "availability": "\(availability)"
        }
        """
    }

    static let catalogApp = """
    {
      "id": "app_7f3k2",
      "name": "Lumen Notes",
      "subtitle": "Заметки и списки",
      "icon_url": "https://cdn.istore.example/icons/lumen.png",
      "category": { "id": "productivity", "name": "Продуктивность" },
      "rating": 4.7,
      "rating_count": 1280,
      "version": "3.2.0",
      "size_bytes": 48211968,
      "min_os": "15.0",
      "tint_light": "#0041DC",
      "tint_dark": "#6AA2E3",
      "bg_color": "#EAF1FF",
      "badge": "updated",
      "availability": "available",
      "description": "Быстрые заметки.",
      "whats_new": "Исправления",
      "developer": "Lumen Labs",
      "bundle_id": "com.lumenlabs.notes",
      "age_rating": "4+",
      "languages": ["RU", "EN"],
      "released_at": "2026-10-20T10:00:00Z",
      "updated_at": "2026-10-28T10:00:00.123Z",
      "screenshots": [{ "url": "https://cdn.istore.example/s1.png", "width": 1290, "height": 2796 }],
      "info": [{ "label": "Разработчик", "value": "Lumen Labs" }],
      "similar": [\(summary(id: "app_similar"))]
    }
    """

    static let groupings = """
    {
      "tab": "today",
      "revision": 42,
      "rooms": [
        {
          "id": "room_hero_today",
          "style": "hero_carousel",
          "title": null,
          "subtitle": null,
          "items": [\(summary(id: "app_a"))],
          "hero": [{
            "app": \(summary(id: "app_a")),
            "headline": "Новое",
            "title": "Порядок в мыслях",
            "image_url": "https://cdn.istore.example/hero.jpg",
            "gradient": ["#0041DC", "#92BDEF"]
          }],
          "categories": [],
          "has_more": false
        },
        {
          "id": "room_shelf",
          "style": "shelf_one",
          "title": "Выбор редакции",
          "subtitle": "Лучшее за неделю",
          "items": [\(summary(id: "app_b")), \(summary(id: "app_c"))],
          "hero": [],
          "categories": [],
          "has_more": true
        },
        {
          "id": "room_cards",
          "style": "shelf_two",
          "title": "Крупно",
          "subtitle": null,
          "items": [\(summary(id: "app_d"))],
          "has_more": false
        },
        {
          "id": "room_chips",
          "style": "chips",
          "title": "Категории",
          "subtitle": null,
          "items": [],
          "hero": [],
          "categories": [{ "id": "productivity", "name": "Продуктивность", "sf_symbol": "checkmark.circle" }],
          "has_more": false
        },
        {
          "id": "room_future",
          "style": "video_wall",
          "title": null,
          "subtitle": null,
          "items": [],
          "hero": [],
          "categories": [],
          "has_more": false
        }
      ]
    }
    """

    static let roomPage = """
    {
      "room": { "id": "room_shelf", "title": "Выбор редакции", "style": "shelf_one" },
      "items": [\(summary(id: "app_b"))],
      "next_cursor": "c2"
    }
    """

    static let categoryPage = """
    {
      "category": { "id": "productivity", "name": "Продуктивность" },
      "items": [\(summary(id: "app_b"))],
      "next_cursor": null
    }
    """

    static let versions = """
    {
      "items": [
        { "version": "3.2.0", "build": "320", "released_at": "2026-10-28T10:00:00Z", "notes": "Исправления", "size_bytes": 48211968 },
        { "version": "3.1.0", "build": 310, "released_at": "2026-09-01T10:00:00Z", "notes": null, "size_bytes": null }
      ],
      "next_cursor": null
    }
    """

    static let account = """
    {
      "id": "acc_1",
      "display_name": "Устройство Ирины",
      "plan": { "id": "month", "name": "1 месяц", "period_months": 1 },
      "status": "active",
      "expires_at": "2026-12-02T00:00:00Z",
      "renew_url": "https://istore.example/renew?acc=acc_1",
      "created_at": "2026-11-02T12:00:00Z"
    }
    """

    static let activateResponse = """
    { "token": "tok_123", "account": \(account) }
    """

    static let profile = """
    {
      "account": \(account),
      "device": { "id": "dev_1", "model": "iPhone16,2", "os_version": "18.1", "install_id_last4": "a1b2" },
      "client": { "locale": "ru", "app_build": "1", "last_seen": "2026-11-02T12:00:00Z" }
    }
    """

    static let storeOpen = """
    { "state": "open", "closed": null }
    """

    static let storeClosed = """
    {
      "state": "closed",
      "closed": {
        "title": "Техработы",
        "message": "Скоро вернёмся",
        "reopens_at": "2026-11-02T18:00:00Z",
        "links": [{ "title": "Канал", "url": "https://t.me/istore" }]
      }
    }
    """

    static let clientVersion = """
    {
      "latest_version": "1.2.0",
      "latest_build": 120,
      "min_supported_build": 100,
      "update_available": true,
      "mandatory": false,
      "release_notes": "Новое",
      "update_url": "itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.istore.example%2Fm.plist"
    }
    """

    static func grant(status: String, itms: Bool = true, errorCode: String? = nil, id: String = "ins_1") -> String {
        let code = errorCode.map { "\"\($0)\"" } ?? "null"
        let itmsValue = itms
            ? "\"itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.istore.example%2Fm.plist\""
            : "null"
        return """
        {
          "install_id": "\(id)",
          "app_id": "app_a",
          "version": "1.0",
          "status": "\(status)",
          "error_code": \(code),
          "manifest_url": "https://api.istore.example/api/v1/catalog/installs/\(id)/manifest.plist?t=x",
          "itms_url": \(itmsValue),
          "size_bytes": 48211968,
          "sha256": "abc",
          "expires_at": "2026-11-02T12:30:00Z"
        }
        """
    }

    static let changes = """
    {
      "revision": 45,
      "changes": [
        { "revision": 43, "kind": "app_upsert", "app_id": "app_a", "app": \(summary(id: "app_a")) },
        { "revision": 44, "kind": "app_removed", "app_id": "app_b", "app": null },
        { "revision": 45, "kind": "rooms_changed", "app_id": null, "app": null }
      ],
      "has_more": false,
      "reset": false
    }
    """

    static let search = """
    {
      "items": [\(summary(id: "app_a"))],
      "next_cursor": "n1",
      "corrected_query": "lumen"
    }
    """

    static let hints = """
    { "hints": [{ "text": "lumen notes", "app_id": "app_a" }, { "text": "notes", "app_id": null }] }
    """

    static let error = """
    { "error": { "code": "invalid_code", "message": "Код не найден" } }
    """
}

extension String {
    var data: Data { Data(utf8) }
}
